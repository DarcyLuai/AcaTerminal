import SwiftUI
import AppKit
import CryptoKit
import AcaCore

@main struct AdvancedFlowChecks {
    struct Failure: Error { var message: String }
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws { guard value() else { throw Failure(message: message) }; count += 1; print("PASS " + message) }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }; throw Failure(message: "Timed out")
    }
    @MainActor static func main() { Task { @MainActor in await run() }; NSApplication.shared.run() }
    @MainActor static func run() async {
        do {
            guard let directory = ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"], !FileManager.default.fileExists(atPath: directory), CommandLine.arguments.count == 2 else { throw Failure(message: "Requires NEW isolated workspace and PDF") }
            UserDefaults.standard.set(false, forKey: "research.autoRefresh")
            let store = WorkspaceStore(); try await wait { store.ready }
            let url = URL(fileURLWithPath: CommandLine.arguments[1]); let original = SHA256.hash(data: try Data(contentsOf: url))
            var paper = ResearchObject(title: "Reading source · QA fixture", doi: "10.48550/arXiv.2205.01833")
            paper.sources = [.init(provider: "local-pdf", externalID: "qa-pdf", url: url)]
            let project = ResearchProject(title: "Political evaluation · QA fixture", question: "How does political evaluation shape risk?")
            paper.projects = [project.id]
            let a = Claim(projectID: project.id, text: "Political evaluation shapes risky choices.")
            let b = Claim(projectID: project.id, text: "Institutional constraints qualify the mechanism.")
            _ = store.change { $0.objects = [paper]; $0.projects = [project]; $0.claims = [a, b] }
            store.openReader(paper); try await wait { store.reader?.loading == false }
            let reader = store.reader!
            guard let page = reader.pdfView.document?.page(at: 2), let selected = page.selection(for: NSRange(location: 0, length: min(40, (page.string ?? "").utf16.count))) else { throw Failure(message: "PDF requires selectable page 3") }
            reader.pdfView.setCurrentSelection(selected, animate: false); reader.selectionChanged()
            guard let selection = reader.selection else { throw Failure(message: "No selection") }
            var evidence = Evidence(paperID: paper.id, page: selection.page, quote: selection.quote)
            evidence.documentID = reader.documentID; evidence.locations = selection.locations
            try check(store.change { try $0.saveEvidence(evidence, projectID: project.id, claimID: a.id); try $0.addClaimRelation(.init(projectID: project.id, sourceClaimID: b.id, targetClaimID: a.id, relationship: .qualifies)) }, "Reader selection persists as linked graph evidence")
            store.closeReader(); store.openEvidence(evidence); try await wait { store.reader?.loading == false }
            try check(store.reader?.pdfView.document?.index(for: store.reader!.pdfView.currentSelection!.pages[0]) == 2, "Graph evidence opens PDF at original page and selection")
            var differentVersion = evidence; differentVersion.documentID = "different-version"
            try check(store.reader!.reveal(differentVersion), "Version mismatch uses exact quote match on saved page")
            differentVersion.quote = "passage absent from PDF"; differentVersion.locations = nil
            try check(!store.reader!.reveal(differentVersion), "Missing passage reports page-only fallback without fabricated selection")
            let seed = DiscoveryWork(id: "W1", object: paper, references: ["W9"], authorIDs: ["A1"], topicIDs: ["T1"])
            var discovered = ResearchObject(title: "Political evaluation and risk: a new test", authors: [.init("Research Author")], year: 2026, doi: "10.1234/qa-discovery")
            discovered.sources = [.init(provider: "openalex", externalID: "W2", url: URL(string: "https://openalex.org/W2"))]
            discovered.abstract = "This test challenges political evaluation and introduces a measurement method."
            let work = DiscoveryWork(id: "W2", object: discovered, references: ["W1", "W9"], authorIDs: ["A1"], topicIDs: ["T1"], publicationDate: Date(), citationCount: 60)
            let profile = ProjectResearchProfile(database: store.database, projectID: project.id)
            let baseline = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: [], checkedAt: Date().addingTimeInterval(-30)))
            let current = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: [work]))
            _ = store.change { $0.recordDiscovery(baseline); $0.recordDiscovery(current) }
            try check(store.database.unreviewedChanges(projectID: project.id).count == 1, "Project change set feeds Today")
            var broughtForward = false; store.presentMainWindow = { broughtForward = true }
            store.notifications.onProject?(project.id)
            try check(broughtForward && store.reader == nil && store.selectedProject == project.id && store.projectTab == "What's New", "Aggregated notification routes to the correct project's changes")
            let imported = store.importDiscovery(work, projectID: project.id); _ = store.importDiscovery(work, projectID: project.id)
            try check(imported != nil && store.database.objects.count == 2 && store.database.objects.last?.projects == [project.id], "Discovery imports idempotently into existing Library/Project")
            store.feedback(work.id, projectID: project.id, judgment: .notRelevant)
            try check(store.database.discoveryFeedback?.last?.judgment == .notRelevant, "Discovery feedback persists locally")
            await store.notifyLiteratureChanges(project.id); await store.notifyLiteratureChanges(project.id)
            try check(store.database.literatureChanges?.allSatisfy { $0.notificationClaimedAt != nil } == true, "Notification claim persists before OS delivery; no duplicate scheduling")
            guard await store.savedBarrier() else { throw Failure(message: "Save failed") }
            let reopened = WorkspaceStore(); try await wait { reopened.ready }
            try check(reopened.database.claimRelations?.count == 1 && reopened.database.discoveryCaches?.count == 1 && reopened.database.literatureSnapshots?.count == 2, "Graph, discovery and literature history survive restart")
            let after = SHA256.hash(data: try Data(contentsOf: url))
            try check(after == original, "Graph source jumps leave original PDF bytes unchanged")
            print("\(count) advanced integration assertions passed. Fixture workspace retained for visual QA only: \(directory)")
            exit(0)
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
