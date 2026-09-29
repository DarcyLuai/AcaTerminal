import SwiftUI
import AcaCore

struct ProjectsView: View {
    @AppStorage("interfaceLanguage") private var language = "system"
    @AppStorage("projects.showList") private var showList = true
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    var project: ResearchProject? { store.database.projects.first { $0.id == store.selectedProject } }
    var listVisible: Bool { showList || project == nil }
    var section: String {
        switch store.projectTab {
        case "Claims", "Graph": return "Argument"
        case "Timeline", "What's New": return "Activity"
        default: return "Literature"
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            projectList.frame(width: listVisible ? 220 : 0).opacity(listVisible ? 1 : 0).clipped().allowsHitTesting(listVisible).accessibilityHidden(!listVisible)
            if listVisible { Divider() }
            if let project = project {
                VStack(spacing: 0) {
                    projectHeader(project)
                    Divider()
                    Group {
                        switch store.projectTab {
                        case "Graph": ClaimGraphView(project: project)
                        case "Claims": ProjectClaimsView(project: project)
                        case "Discover": ProjectDiscoveryView(project: project)
                        case "What's New": ProjectChangesView(project: project)
                        case "Timeline": ProjectTimelineView(project: project)
                        default: ProjectPapersView(project: project)
                        }
                    }.id(project.id).transition(.opacity).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            } else { EmptyPage(title: tr("Start with a question"), detail: tr("Projects bring papers, claims, evidence and manuscripts into one research workflow."), icon: "square.stack.3d.up") }
        }
    }
    var projectList: some View {
        VStack(spacing: 0) {
            HStack { Text(tr("Projects")).font(.system(size: 21, design: .serif)); Spacer(); Button { store.sheet = .project } label: { Image(systemName: "plus") }.accessibilityLabel(tr("New project")) }.padding(20)
            List(store.database.projects, selection: $store.selectedProject) { project in
                Text(project.title).font(.system(size: 14)).lineLimit(2).padding(.vertical, 12).tag(project.id)
            }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
    func projectHeader(_ project: ResearchProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Button { withAnimation(AcaMotion.panels(reduced: reduced)) { showList.toggle() } } label: { Image(systemName: "sidebar.left").frame(width: 28, height: 28) }.buttonStyle(AcaButtonStyle(inset: 0)).help(tr(listVisible ? "Hide project list" : "Show project list")).accessibilityLabel(tr(listVisible ? "Hide project list" : "Show project list"))
                VStack(alignment: .leading, spacing: 10) {
                    Text(project.title).font(.system(size: 25, design: .serif)).textSelection(.enabled)
                    if !project.question.isEmpty { Text(project.question).font(.system(size: 14)).foregroundColor(.secondary).lineSpacing(3).lineLimit(3).help(project.question).textSelection(.enabled) }
                }
                Spacer(minLength: 0)
                AcaTexProjectControls(projectID: project.id)
            }
            HStack(spacing: 8) {
                ForEach(["Literature", "Argument", "Activity"], id: \.self) { tab in
                    Button { withAnimation(AcaMotion.transition(reduced: reduced)) { store.projectTab = tab == "Argument" ? "Claims" : tab == "Activity" ? "What's New" : "Overview" } } label: { Text(tr(tab)).padding(.horizontal, 9) }.buttonStyle(AcaButtonStyle(selected: section == tab))
                }
                Spacer(minLength: 8)
                if section == "Argument" {
                    Picker(tr("Argument view"), selection: $store.projectTab) { Text(tr("List")).tag("Claims"); Text(tr("Graph")).tag("Graph") }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                } else if section == "Activity" {
                    Picker(tr("Activity view"), selection: $store.projectTab) { Text(tr("Changes")).tag("What's New"); Text(tr("Timeline")).tag("Timeline") }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
            }
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 14)
    }
}
struct ProjectSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 26) { content }.frame(maxWidth: 900, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .center) } }
}
struct ProjectPapersView: View {
    @EnvironmentObject var store: WorkspaceStore
    var project: ResearchProject
    @State private var addingPapers = false
    @State private var search = ""
    var papers: [ResearchObject] { store.database.objects.filter { $0.projects.contains(project.id) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.authors.contains { $0.name.localizedCaseInsensitiveContains(search) }) } }
    var body: some View {
        ProjectSurface {
            HStack(spacing: 12) {
                TextField(tr("Search project papers…"), text: $search).textFieldStyle(.roundedBorder)
                Menu { Button(tr("Import documents…")) { store.chooseDocuments(projectID: project.id) }; Button(tr("Add papers…")) { addingPapers = true } } label: { Image(systemName: "plus") }.help(tr("Add papers…"))
                Button(tr("Discover related papers")) { store.projectTab = "Discover" }
            }
            if papers.isEmpty { Text(tr("Import documents or add papers from your Library.")).foregroundColor(.secondary).padding(.vertical, 22) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(papers) { paper in
                    Button { store.openReader(paper) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(paper.title).font(.system(size: 18, design: .serif))
                            Text(([paper.authors.map(\.name).joined(separator: ", "), paper.year.map(String.init) ?? "", tr(paper.type.rawValue.capitalized)]).filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    }.buttonStyle(AcaButtonStyle(inset: 5))
                    Divider().opacity(0.5)
                }
            }
        }.sheet(isPresented: $addingPapers) { ProjectPaperPicker(project: project) }
    }
}
struct ProjectClaimsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var newClaim = ""
    var project: ResearchProject
    var body: some View { ProjectSurface {
                    VStack(alignment: .leading, spacing: 20) {
                        AcaTexConnectionStatus(projectID: project.id)
                        ForEach(ResearchMarkType.arguments, id: \.self) { type in
                            let marks = claims(project).filter { $0.researchType == type }
                            if !marks.isEmpty {
                                VStack(alignment: .leading, spacing: 18) {
                                    SectionCaption(text: type.title)
                                    ForEach(marks) { claim in ResearchMarkRow(claim: claim) }
                                }.padding(.vertical, 8)
                            }
                        }
                        HStack { TextField(tr("Write a claim…"), text: $newClaim).textFieldStyle(.roundedBorder); Button(tr("Add")) { if store.change({ $0.claims.append(Claim(projectID: project.id, text: newClaim.trimmingCharacters(in: .whitespacesAndNewlines))) }) { newClaim = "" } }.disabled(newClaim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
                    let unlinked = store.database.evidence.filter { $0.projectID == project.id && !claims(project).flatMap(\.evidence).contains($0.id) }
                    if !unlinked.isEmpty {
                        SectionCaption(text: "Evidence · awaiting a claim")
                        ForEach(unlinked) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.quote.isEmpty ? item.note : item.quote).textSelection(.enabled)
                                Text(pageLabel(item.page)).font(.caption).foregroundColor(.secondary)
                                Menu(tr("Attach to Claim")) { ForEach(claims(project)) { claim in Button(claim.text) { store.change { try $0.attachEvidence(item.id, to: claim.id) } } } }
                            }
                        }
                    }
    } }
    func claims(_ project: ResearchProject) -> [Claim] { store.database.claims.filter { $0.projectID == project.id } }
}
struct ProjectEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var question = ""
    var body: some View { EditorFrame(title: tr("New Research Project"), saveTitle: tr("Create Project"), valid: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: {
        let project = ResearchProject(title: title.trimmingCharacters(in: .whitespacesAndNewlines), question: question)
        if store.change({ $0.projects.append(project) }) { store.showProject(project.id); dismiss() }
    }) { TextField(tr("Project name"), text: $title); Text(tr("Research question")).font(.caption); TextEditor(text: $question).frame(height: 120).border(Color.secondary.opacity(0.2)) } }
}
struct ProjectPaperPicker: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var project: ResearchProject
    @State private var selected: Set<UUID> = []
    var body: some View { EditorFrame(title: trf("Add to %@", project.title), valid: !selected.isEmpty, save: {
        if store.change({ db in for i in db.objects.indices where selected.contains(db.objects[i].id) && !db.objects[i].projects.contains(project.id) { db.objects[i].projects.append(project.id) } }) { dismiss() }
    }) { if store.database.objects.isEmpty { Text(tr("Add papers to your library first.")).foregroundColor(.secondary) }; List(store.database.objects.filter { !$0.projects.contains(project.id) }) { paper in Toggle(paper.title, isOn: Binding(get: { selected.contains(paper.id) }, set: { if $0 { selected.insert(paper.id) } else { selected.remove(paper.id) } })) }.frame(height: 300); Text(tr("Select the papers to include.")).font(.caption).foregroundColor(.secondary) } }
}
struct NoteEvidenceEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var paper: ResearchObject
    var initialNote = ""
    @State private var text = ""; @State private var quote = ""; @State private var page = ""
    @State private var asEvidence = false
    @State private var claimID: UUID?
    @State private var relationship = EvidenceRelationship.supports
    var body: some View { EditorFrame(title: tr(asEvidence ? "Save as Evidence" : "Research Note"), valid: (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (asEvidence && !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) && (!asEvidence || claimID != nil), save: save) {
        Text(paper.title).font(.caption).foregroundColor(.secondary)
        if !store.database.notes.filter({ $0.paperID == paper.id }).isEmpty {
            Menu(tr("Use an existing note")) { ForEach(store.database.notes.filter { $0.paperID == paper.id }) { note in Button(String(note.text.prefix(70))) { text = note.text; asEvidence = true } } }
        }
        Text(tr("Note")).font(.caption); TextEditor(text: $text).frame(height: 100).border(Color.secondary.opacity(0.2))
        Toggle(tr("Attach as evidence to a claim"), isOn: $asEvidence)
        if asEvidence {
            Text(tr("Paste a selected excerpt from your PDF (optional)")).font(.caption); TextEditor(text: $quote).frame(height: 85).border(Color.secondary.opacity(0.2))
            HStack { TextField(tr("Page / location"), text: $page); Picker(tr("Relationship"), selection: $relationship) { ForEach(EvidenceRelationship.selectable, id: \.self) { Text(tr($0.rawValue.capitalized)).tag($0) } } }
            Picker(tr("Claim"), selection: $claimID) { Text(tr("Choose a claim")).tag(nil as UUID?); ForEach(store.database.claims) { claim in Text((store.database.projects.first { $0.id == claim.projectID }?.title ?? "") + " — " + claim.text).tag(Optional(claim.id)) } }
            if store.database.claims.isEmpty { Text(tr("Create a project and claim first.")).font(.caption).foregroundColor(.secondary) }
        }
    }.onAppear { text = initialNote; asEvidence = !initialNote.isEmpty } }
    func save() { if store.change({ db in
        if asEvidence, let claimID = claimID { try db.addEvidence(.init(paperID: paper.id, page: page, quote: quote, note: text, relationship: relationship), to: claimID) }
        else { db.notes.append(.init(paperID: paper.id, text: text)) }
    }) { dismiss() } }
}
