import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AcaCore

struct LibraryView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @State private var search = ""
    @State private var source = "All"
    @State private var collection = ""
    var papers: [ResearchObject] { store.database.objects.filter { paper in
        (source == "All" || (source == "Zotero" ? paper.sources.contains { ["zotero", "zotero-pdf"].contains($0.provider) } : !paper.sources.contains { ["zotero", "zotero-pdf"].contains($0.provider) })) &&
        (collection.isEmpty || paper.sources.contains { ($0.metadata["collections"] ?? "").components(separatedBy: ",").contains(collection) }) &&
        (search.isEmpty || ([paper.title, paper.authors.map(\.name).joined(separator: " "), paper.doi ?? "", paper.tags.joined(separator: " ")].joined(separator: " ").localizedCaseInsensitiveContains(search)))
    }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack { Text(tr("Library")).font(.system(size: 25, design: .serif)); Spacer(); Button { store.chooseDocuments() } label: { Image(systemName: "doc.badge.plus") }.help(tr("Import documents…")).accessibilityLabel(tr("Import documents…")); Menu { Button(tr("Add metadata only…")) { store.sheet = .paper } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22) }.padding(22)
                VStack(spacing: 12) {
                    TextField(tr("Search papers, authors, DOI"), text: $search).textFieldStyle(.roundedBorder)
                    Picker(tr("Library source"), selection: $source) { Text(tr("All")).tag("All"); Text(tr("Local")).tag("Local"); Text(tr("Zotero")).tag("Zotero") }.pickerStyle(.segmented).labelsHidden()
                    if !store.database.collections.isEmpty { Picker(tr("Collection"), selection: $collection) { Text(tr("All collections")).tag(""); ForEach(store.database.collections) { Text($0.name).tag($0.id) } } }
                }.padding(.horizontal, 20).padding(.bottom, 16)
                Divider()
                LibraryTable(papers: papers, database: store.database, selection: $store.selectedPaper, open: { store.openReader($0) }, markRead: { store.markRead($0.id) })
                HStack { Text(trf("%d items", papers.count)); Spacer(); Text(tr("Available offline")) }.font(.system(size: 10)).foregroundColor(.secondary).padding(16)
            }.frame(minWidth: 270, idealWidth: 320, maxWidth: 380)
            if let id = store.selectedPaper, let paper = store.database.objects.first(where: { $0.id == id }) { PaperDetail(paper: paper).id(id) }
            else { EmptyPage(title: tr("Your reading, connected"), detail: papers.isEmpty ? "Import a PDF or Word document to begin. Bibliographic details can be added later." : "Select a paper to read, take notes, or connect evidence to a claim.", icon: "doc.text") }
        }
    }
}
struct PaperDetail: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    var paper: ResearchObject
    @State private var writing = false
    @State private var editingMetadata = false
    @State private var noteDraft = ""
    var body: some View {
        Page(title: paper.title, subtitle: paper.authors.map(\.name).joined(separator: ", ")) {
            Text([paper.venue, paper.year.map(String.init) ?? "", tr(paper.type.rawValue.capitalized)].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundColor(.secondary).font(.caption)
            HStack {
                Button(tr("Open Reader"), action: read)
                Button(tr("Note")) { noteDraft = ""; writing = true }
                Button(tr("Cite")) { let text = "\(paper.authors.map(\.name).joined(separator: ", ")) (\(paper.year.map(String.init) ?? "n.d.")). \(paper.title). \(paper.venue). \(paper.doi.map { "https://doi.org/\($0)" } ?? "")"; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); store.message = "Citation copied. Check the formatting required by your journal." }
                Menu(tr("Add to Project")) { if store.database.projects.isEmpty { Button(tr("Create a project…")) { store.sheet = .project } }; ForEach(store.database.projects) { project in Button(project.title) { store.change { db in if let i = db.objects.firstIndex(where: { $0.id == paper.id }), !db.objects[i].projects.contains(project.id) { db.objects[i].projects.append(project.id); db.objects[i].updatedAt = Date() } } }.disabled(paper.projects.contains(project.id)) } }.fixedSize()
                Menu { Button(tr("Find full text")) { store.fullTextObject = paper }; Button(tr("Edit details…")) { editingMetadata = true }; Button(tr("Attach local PDF…"), action: attachPDF); Button(tr("Export for AcaTex…"), action: exportCitation) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel(tr("More paper actions"))
            }.controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 14) { SectionCaption(text: "Abstract"); Text(paper.abstract.isEmpty ? tr("No abstract available. You can still add notes and evidence.") : paper.abstract).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled) }
            VStack(alignment: .leading, spacing: 16) {
                SectionCaption(text: "Research")
                info("Notes", "\(store.database.notes.filter { $0.paperID == paper.id }.count)")
                info("Claims", "\(store.database.claims.filter { $0.sources.contains(paper.id) }.count)")
                info("Projects", "\(paper.projects.count)")
                ForEach(store.database.notes.filter { $0.paperID == paper.id }) { note in VStack(alignment: .leading, spacing: 10) { Text(note.text).textSelection(.enabled); Button(tr("Save as Evidence…")) { noteDraft = note.text; writing = true }.font(.caption) }.padding(.vertical, 8) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack { SectionCaption(text: "Impact"); Spacer(); Button(tr("Refresh OpenAlex")) { Task { await store.refreshMetrics(paper) } }.disabled(store.busy || (paper.doi == nil && !paper.sources.contains { $0.provider == "openalex" })) }
                if let metrics = store.database.latestMetrics(for: paper.id) { info("Citations", metrics.citationCount.formatted()); info("Source", metrics.provider); Text(metrics.updatedAt.formatted(.dateTime.locale(L10n.locale).year().month().day())).font(.caption).foregroundColor(.secondary) }
                else { Text(tr(paper.doi == nil ? "Add a DOI in Edit Details to retrieve citation data." : "No citation snapshot yet.")).foregroundColor(.secondary).font(.caption) }
            }
            VStack(alignment: .leading, spacing: 16) { SectionCaption(text: "Sources"); if let doi = paper.doi { Text(doi).font(.caption).textSelection(.enabled) }; ForEach(paper.sources) { source in info(source.provider == "local-pdf" ? "Local PDF" : source.provider == "local-document" ? "Original document" : source.provider.capitalized, "✓") } }
        }.sheet(isPresented: $writing) { NoteEvidenceEditor(paper: paper, initialNote: noteDraft) }.sheet(isPresented: $editingMetadata) { PaperEditor(existing: paper) }
    }
    func info(_ label: String, _ value: String) -> some View { HStack { Text(tr(label)).foregroundColor(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 13)) }
    func read() { store.openReader(paper) }
    func attachPDF() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.change { db in if let i = db.objects.firstIndex(where: { $0.id == paper.id }) { db.objects[i].sources.removeAll { $0.provider == "local-pdf" }; db.objects[i].sources.append(.init(provider: "local-pdf", externalID: paper.id.uuidString, url: url)) } }
    }
    func exportCitation() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "citation.acaresearch.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let name = paper.authors.first?.name.split(separator: " ").last.map(String.init) ?? "Research"; let key = name + (paper.year.map(String.init) ?? "") + "_" + paper.id.uuidString.prefix(6)
            let data = try JSONResearchBridge().export(.init(object: paper, citeKey: key)); try data.write(to: url, options: .atomic); store.message = "AcaResearchExchange exported for AcaTex integration." } catch { store.error = error.localizedDescription }
    }
}
struct PaperEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var existing: ResearchObject? = nil
    @State private var title = ""; @State private var authors = ""; @State private var year = ""; @State private var doi = ""; @State private var venue = ""; @State private var abstract = ""
    @State private var kind = ObjectKind.paper
    @State private var candidate: UUID?
    @State private var reviewed = false
    @State private var pending: ResearchObject?
    var body: some View {
        EditorFrame(title: tr(existing == nil ? "Add to Library" : "Edit details…"), saveTitle: tr(existing == nil ? "Add Paper" : "Save"), valid: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (year.isEmpty || Int(year).map { (1000...2200).contains($0) } == true), save: save) {
            TextField(tr("Title"), text: $title); TextField(tr("Authors, separated by semicolons"), text: $authors)
            HStack { TextField(tr("Year"), text: $year); Picker(tr("Type"), selection: $kind) { ForEach(ObjectKind.allCases, id: \.self) { Text(tr($0.rawValue.capitalized)).tag($0) } } }
            TextField(tr("Journal / Publisher"), text: $venue); TextField(tr("DOI (optional)"), text: $doi)
            Text(tr("Abstract")).font(.caption).foregroundColor(.secondary); TextEditor(text: $abstract).frame(height: 90).border(Color.secondary.opacity(0.2))
        }.onAppear { if let item = existing { title = item.title; authors = item.authors.map(\.name).joined(separator: "; "); year = item.year.map(String.init) ?? ""; doi = item.doi ?? ""; venue = item.venue; abstract = item.abstract; kind = item.type } }.alert("Possible duplicate", isPresented: $reviewed) {
            Button(tr("Merge with existing")) { if let pending = pending, let candidate = candidate { commit(pending, into: candidate) } }
            Button(tr("Keep separate")) { if let pending = pending { commit(pending, into: nil) } }
            Button(tr("Cancel"), role: .cancel) {}
        } message: { Text(tr("The title, author and year match an existing item. Review its identity before merging. The existing title and research links will be preserved.")) }
    }
    func save() {
        if let existing = existing {
            if store.change({ db in
                guard let i = db.objects.firstIndex(where: { $0.id == existing.id }) else { return }
                db.objects[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                db.objects[i].authors = authors.split(separator: ";").map { Author($0.trimmingCharacters(in: .whitespaces)) }
                db.objects[i].year = Int(year); db.objects[i].doi = ResearchObjectResolver.doi(doi)
                db.objects[i].venue = venue; db.objects[i].abstract = abstract; db.objects[i].type = kind; db.objects[i].updatedAt = Date()
            }) { dismiss() }
            return
        }
        var item = ResearchObject(title: title.trimmingCharacters(in: .whitespacesAndNewlines), authors: authors.split(separator: ";").map { Author($0.trimmingCharacters(in: .whitespaces)) }, year: Int(year), doi: doi.isEmpty ? nil : ResearchObjectResolver.doi(doi)); item.type = kind; item.venue = venue; item.abstract = abstract; item.sources = [.init(provider: "local", externalID: item.id.uuidString)]
        switch ResearchObjectResolver().resolve(item, in: store.database.objects) {
        case .match(let id): commit(item, into: id)
        case .possible(let ids): candidate = ids.first; pending = item; reviewed = true
        case .new: commit(item, into: nil)
        }
    }
    func commit(_ item: ResearchObject, into id: UUID?) {
        if store.change({ db in if let id = id, let i = db.objects.firstIndex(where: { $0.id == id }) { db.objects[i] = ResearchObjectResolver().merge(item, into: db.objects[i]) } else { db.objects.append(item) } }) { store.showPaper(id ?? item.id); dismiss() }
    }
}
struct EditorFrame<Content: View>: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @Environment(\.dismiss) var dismiss
    var title: String; var saveTitle = "Save"; var valid = true; var save: () -> Void; @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 22) { Text(title).font(.system(size: 25, design: .serif)); content.textFieldStyle(.roundedBorder); Divider(); HStack { Spacer(); Button(tr("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(tr(saveTitle), action: save).keyboardShortcut(.defaultAction).disabled(!valid) } }.padding(32).frame(width: 530) }
}
