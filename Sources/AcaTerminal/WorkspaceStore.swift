import SwiftUI
import AcaCore
import AcaStorage
import AcaConnectors

enum Destination: String, CaseIterable, Identifiable {
    case today = "Today", library = "Library", projects = "Projects", submissions = "Submissions", impact = "My Research", zotero = "Zotero", orcid = "ORCID", openalex = "OpenAlex", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .library: return "books.vertical"
        case .projects: return "square.stack.3d.up"
        case .submissions: return "paperplane"
        case .impact: return "chart.xyaxis.line"
        case .zotero: return "z.square"
        case .orcid: return "person.crop.circle"
        case .openalex: return "globe"
        case .settings: return "gearshape"
        }
    }
}
enum EditorSheet: String, Identifiable { case paper, project, submission; var id: String { rawValue } }
@MainActor final class WorkspaceStore: ObservableObject {
    @Published private(set) var database = ResearchDatabase()
    @Published var databaseRevision = 0
    @Published var projectTab = "Overview"
    @Published var markConnecting = false
    @Published var markRefreshing: Set<UUID> = []
    @Published var markErrors: [UUID: String] = [:]
    @Published var discoveryMarkID: UUID?
    var markTasks: [UUID: Task<Void, Never>] = [:]
    var pendingResearchURL: URL?
    @Published var discoveryRefreshing: Set<UUID> = []
    @Published var discoveryErrors: [UUID: String] = [:]
    var discoveryTasks: [UUID: Task<Void, Never>] = [:]
    var projectLaunchTask: Task<Void, Never>?
    var pendingEvidence: Evidence?
    var pendingProjectID: UUID?
    @Published var destination: Destination? = .today
    @Published var selectedPaper: UUID?
    @Published var selectedProject: UUID?
    @Published var selectedSubmission: UUID?
    @Published var showInformation = false
    @Published var sheet: EditorSheet?
    @Published var error: String?
    @Published var message: String?
    @Published var busy = false
    @Published var interfaceLanguage = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system" { didSet { UserDefaults.standard.set(interfaceLanguage, forKey: "interfaceLanguage") } }
    @Published private(set) var ready = false
    @Published var pendingSaves = 0
    @Published var saveFailed = false
    @Published var loadingWorkspace = false
    @Published var analytics = ImpactAnalytics(database: ResearchDatabase(), provider: "openalex")
    @Published var analyticsProvider = "openalex" { didSet { rebuildAnalytics() } }
    @Published var impactRefreshing = false
    @Published var impactStatus = ""
    @Published var selectedCitationID: String?
    var presentMainWindow: (() -> Void)?
    var pendingCitationID: String?
    var analyticsTask: Task<Void, Never>?
    var impactTask: Task<Void, Never>?
    let notifications = ResearchNotifications()
    @Published var fullTextObject: ResearchObject?
    @Published var reader: ReaderSession?
    var repository: RepositoryWorker?
    private var workspaceGeneration = UUID()
    var databaseURL: URL = URL(fileURLWithPath: "/")
    let credentials = KeychainStore()
    let httpClient = HTTPClient()
    init() {
        notifications.onCitation = { [weak self] id in self?.showCitation(id) }
        notifications.onProject = { [weak self] id in self?.showResearchChanges(id) }
        notifications.configure(); openWorkspace()
    }
    func openWorkspace() {
        reader?.saveNow()
        guard !busy && pendingSaves == 0 && !saveFailed else { error = "Wait for saving to finish before switching workspaces. If saving failed, export your unsaved research first."; return }
        reader = nil; loadingWorkspace = true; ready = false
        let base = ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AcaTerminal")
        let url = base.appendingPathComponent("research.sqlite")
        let generation = UUID(); workspaceGeneration = generation
        let worker = RepositoryWorker(); repository = worker
        worker.open(url: url, seed: nil) { [weak self] result in
            guard let self = self, self.workspaceGeneration == generation else { return }
            self.loadingWorkspace = false
            switch result {
            case .success(let data):
                self.database = data; self.databaseRevision += 1; self.databaseURL = url; self.ready = true
                self.rebuildAnalytics()
                Task { await self.notifyCitationEvents() }
                if let id = self.pendingCitationID { self.pendingCitationID = nil; self.showCitation(id) }
                self.refreshImpact(manual: false)
                self.selectedPaper = nil; self.selectedProject = nil; self.selectedSubmission = nil; self.message = nil
                if let id = self.pendingProjectID { self.pendingProjectID = nil; self.showResearchChanges(id) }
                self.refreshProjectsOnLaunch()
                self.refreshAcaTex()
                if let url = self.pendingResearchURL { self.pendingResearchURL = nil; self.handleResearchURL(url) }
                if let path = ProcessInfo.processInfo.environment["ACATERMINAL_READER_FIXTURE"], ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"] != nil { self.importLocalPDF(URL(fileURLWithPath: path)) }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
    }
    /// Publish edits immediately, with visible pending/error state. Disk work is serial
    /// and off-main; quit/switch wait for the queue. Failed edits remain exportable.
    @discardableResult func change(_ edit: (inout ResearchDatabase) throws -> Void) -> Bool {
        guard ready, !saveFailed, let repo = repository else { error = "Changes cannot be saved. Export unsaved research from Settings and reopen the workspace."; return false }
        do {
            var next = database; try edit(&next)
            let previous = Dictionary(uniqueKeysWithValues: database.submissions.map { ($0.id, $0) })
            let changedSubmissions = next.submissions.filter { item in previous[item.id].map { $0.status != item.status || $0.statusRaw != item.statusRaw } ?? false }
            database = next; databaseRevision += 1; pendingSaves += 1
            repo.save(next) { [weak self] result in
                guard let self = self else { return }; self.pendingSaves -= 1
                if case .success = result, UserDefaults.standard.object(forKey: "notifications.submissions") as? Bool != false {
                    for item in changedSubmissions { Task { await self.notifications.send(id: "submission|" + item.id.uuidString + "|" + (item.history.last?.id.uuidString ?? ""), title: tr("Submission changed"), body: item.title + "\n" + tr(item.status.title)) } }
                }
                if case .failure(let error) = result, !self.saveFailed { self.saveFailed = true; self.error = "Changes are still in memory but could not be saved. Export unsaved research in Settings. " + error.localizedDescription }
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func prepareToQuit(_ completion: @escaping (Bool) -> Void) {
        markTasks.values.forEach { $0.cancel() }; impactTask?.cancel(); projectLaunchTask?.cancel(); discoveryTasks.values.forEach { $0.cancel() }
        reader?.saveNow()
        guard let repository = repository else { completion(true); return }
        repository.drain { [weak self] in completion(self?.saveFailed != true) }
    }
    func showPaper(_ id: UUID) { selectedPaper = id; destination = .library }
    func showProject(_ id: UUID) { selectedProject = id; destination = .projects }
    func showSubmission(_ id: UUID) { selectedSubmission = id; destination = .submissions }
}
