import SwiftUI
import AcaCore

enum Palette {
    static let accent = Color(red: 0.37, green: 0.43, blue: 0.37)
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.105, green: 0.112, blue: 0.108) : Color(red: 0.978, green: 0.973, blue: 0.954) }
}
struct ShellView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("appearance") var appearance = "system"
    var body: some View {
        ZStack {
        if let reader = store.reader { AcademicReader(session: reader).id(reader.paperID).transition(.opacity) }
        else { mainNavigation.transition(.opacity) }
        }.tint(Palette.accent)
        .alert("AcaTerminal", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button(tr("OK")) { store.error = nil } } message: { Text(tr(store.error ?? "")) }
        .sheet(item: $store.fullTextObject) { FullTextView(paper: $0) }
        .sheet(isPresented: $store.showInformation) { ApplicationInformationView() }
        .sheet(item: $store.sheet) { sheet in
            switch sheet { case .paper: PaperEditor(); case .project: ProjectEditor(); case .submission: SubmissionEditor() }
        }
    }
    var mainNavigation: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack { Text(tr("AcaTerminal")).font(.system(size: 16, weight: .medium)); Spacer() }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 22)
                List(selection: $store.destination) {
                    item(.today)
                    Section(tr("Research")) { item(.library); item(.projects); item(.submissions) }
                    Section(tr("Impact")) { item(.impact) }
                    Section(tr("Connected Services")) { item(.zotero); item(.orcid); item(.openalex) }
                    Section { item(.settings) }
                }.listStyle(.sidebar).scrollContentBackground(appearance == "comfort" ? .hidden : .automatic).background(appearance == "comfort" ? Color(red: 0.94, green: 0.93, blue: 0.90) : .clear)
                if store.saveFailed { Button(tr("Unsaved changes · export in Settings")) { store.destination = .settings }.font(.caption).foregroundColor(.secondary).buttonStyle(AcaButtonStyle()).padding(20) }
                else if store.pendingSaves > 0 { Text(tr("Saving…")).font(.caption).foregroundColor(.secondary).padding(20) }
            }.navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let message = store.message { HStack { Text(tr(message)); Spacer(); Button { store.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(AcaButtonStyle()).accessibilityLabel(tr("Dismiss message")) }.font(.caption).padding(12).background(Palette.accent.opacity(0.1)) }
                ZStack { content.id(store.destination).transition(.opacity) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(AcaMotion.transition(reduced: reduceMotion), value: store.destination)
            }.background((appearance == "comfort" ? Color(red: 0.955, green: 0.945, blue: 0.916) : Palette.paper(scheme)).animation(AcaMotion.transition(reduced: reduceMotion), value: appearance))
            .navigationTitle(tr(store.destination?.rawValue ?? "Today"))
            .toolbar { ToolbarItem { if store.busy { ProgressView().controlSize(.small) } } }
        }
    }
    func item(_ destination: Destination) -> some View { Label(tr(destination.rawValue), systemImage: destination.icon).tag(destination).padding(.vertical, 7) }
    @ViewBuilder var content: some View {
        if store.loadingWorkspace { ProgressView(tr("Opening research…")).frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if !store.ready { EmptyPage(title: tr("Your database needs attention"), detail: tr("Reopen AcaTerminal after resolving the error. Existing research has not been replaced."), icon: "externaldrive.badge.exclamationmark") }
        else {
            switch store.destination ?? .today {
            case .today: TodayView()
            case .library: LibraryView()
            case .projects: ProjectsView()
            case .submissions: SubmissionsView()
            case .impact: ImpactView()
            case .zotero, .orcid, .openalex: ServicesView(service: store.destination ?? .zotero).id(store.destination)
            case .settings: PreferencesView()
            }
        }
    }
}
struct Page<Content: View>: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var title: String; var subtitle: String = ""; @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 40) {
        VStack(alignment: .leading, spacing: 9) { Text(title).font(.system(size: 30, weight: .regular, design: .serif)); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary) } }.padding(.bottom, 8)
        content
    }.frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 38).padding(.vertical, 44).frame(maxWidth: .infinity, alignment: .center) } }
}
struct SectionCaption: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var text: String; var body: some View { Text(tr(text)).font(.system(size: 12, weight: .semibold)).tracking(L10n.isChinese ? 0 : 0.5).foregroundColor(.secondary) } }
struct EmptyPage: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var title: String; var detail: String; var icon: String
    var body: some View { VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 30, weight: .ultraLight)).foregroundColor(.secondary); Text(title).font(.system(size: 23, design: .serif)); Text(tr(detail)).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360) }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
struct TodayView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        Page(title: tr("Today"), subtitle: Date().formatted(.dateTime.locale(L10n.locale).weekday(.wide).month(.wide).day())) {
            if store.database.identity != nil {
                VStack(alignment: .leading, spacing: 18) {
                    SectionCaption(text: "New impact")
                    Text(trf("%d newly detected citations this week", store.analytics.newEventsThisWeek) + " · " + store.analytics.provider).font(.system(size: 23, design: .serif))
                    CitationActivityList(limit: 3)
                }
                Divider()
            }
            ResearchChangesToday()
            if store.database.objects.isEmpty && store.database.projects.isEmpty && store.database.submissions.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    Text(tr("Begin with a paper.")).font(.system(size: 25, weight: .light, design: .serif))
                    HStack { Button(tr("Import documents…")) { store.chooseDocuments() }; Button(tr("Connect Zotero")) { store.destination = .zotero } }
                }.padding(.vertical, 25)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    SectionCaption(text: "Submissions")
                    if store.database.submissions.isEmpty { Text(tr("No submissions yet.")).foregroundColor(.secondary) }
                    ForEach(store.database.submissions.filter { $0.status.isActive }.prefix(3)) { item in
                        Button { store.showSubmission(item.id) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 7) { Text(item.title).font(.system(size: 20, design: .serif)); Text(item.journal).foregroundColor(.secondary) }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 7) { Label(tr(item.status.title), systemImage: "circle.dotted"); Text(item.submissionDateUnknown == true || item.source == "openreview" ? trf("Recorded on %@", item.updatedAt.formatted(.dateTime.locale(L10n.locale).month().day())) : trf("Day %d in this stage", max(1, Calendar.current.dateComponents([.day], from: item.history.last?.date ?? item.submittedAt, to: Date()).day! + 1))).font(.caption).foregroundColor(.secondary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(AcaButtonStyle())
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    SectionCaption(text: "Recent impact")
                    if store.database.citationSnapshots.isEmpty { Text(tr("Refresh a paper’s OpenAlex metrics to start tracking impact.")).foregroundColor(.secondary) }
                    ForEach(store.database.objects.filter { store.database.latestMetrics(for: $0.id) != nil }.prefix(3)) { object in
                        if let metrics = store.database.latestMetrics(for: object.id) { HStack { Text(object.title); Spacer(); Text(trf("%d citations", metrics.citationCount)).monospacedDigit(); Text(metrics.provider).font(.caption).foregroundColor(.secondary) } }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    SectionCaption(text: "Continue reading")
                    if let paper = store.database.objects.filter({ $0.lastReadAt != nil }).sorted(by: { $0.lastReadAt! > $1.lastReadAt! }).first {
                        Button { store.openReader(paper) } label: { VStack(alignment: .leading, spacing: 8) { Text(paper.authors.map(\.name).joined(separator: ", ") + " · " + (paper.year.map(String.init) ?? "" )).font(.caption).foregroundColor(.secondary); Text(paper.title).font(.system(size: 20, design: .serif)); if let position = store.database.readingPosition(for: paper.id) { Text(pageLabel(String(position.page + 1)) + " · \(position.progress)%").font(.caption).foregroundColor(.secondary) } } }.buttonStyle(AcaButtonStyle())
                    } else { Text(tr("Open a paper from your library to pick up where you left off.")).foregroundColor(.secondary) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    SectionCaption(text: "Projects")
                    ForEach(store.database.projects.prefix(4)) { project in Button { store.showProject(project.id) } label: {
                        HStack { Text(project.title).font(.system(size: 18, design: .serif)); Spacer(); Text(trf("%d papers · %d claims", store.database.objects.filter { $0.projects.contains(project.id) && [.paper, .book, .dataset].contains($0.type) }.count, store.database.claims.filter { $0.projectID == project.id }.count)).font(.caption).foregroundColor(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }
                    }.buttonStyle(AcaButtonStyle()) }
                }
            }
        }
    }
}
