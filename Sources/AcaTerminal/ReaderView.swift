import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AcaCore

struct AcademicReader: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @ObservedObject var session: ReaderSession
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var scheme
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("reader.width") var width = "comfortable"
    @AppStorage("reader.gap") var gap = "medium"
    @AppStorage("reader.progress") var showProgress = true
    @AppStorage("reader.selection") var selectionToolbar = true
    @State private var outlineTab = "Outline"
    @State private var projectID: UUID?
    @State private var action: SelectionAction?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if session.showSearch {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField(tr("Search this PDF"), text: $session.query).textFieldStyle(.plain).focused($searchFocused).onChange(of: session.query) { _ in session.startSearch() }.onSubmit { session.navigateMatch(1) }
                    if session.searching { ProgressView().controlSize(.mini) }
                    Text("\(max(0, session.matchIndex + 1)) / \(session.matchCount)").font(.caption).monospacedDigit().foregroundColor(.secondary)
                    Button { session.navigateMatch(-1) } label: { Image(systemName: "chevron.up") }.help(tr("Previous result"))
                    Button { session.navigateMatch(1) } label: { Image(systemName: "chevron.down") }.help(tr("Next result"))
                    Button { session.showSearch = false; session.query = ""; session.startSearch() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("Close search"))
                }.padding(.horizontal, 22).padding(.vertical, 10).background(chrome)
            }
            Divider()
            HStack(spacing: 0) {
                outlinePane.frame(width: session.showOutline ? 184 : 0).opacity(session.showOutline ? 1 : 0).clipped().accessibilityHidden(!session.showOutline).allowsHitTesting(session.showOutline)
                if session.showOutline { Divider() }
                ZStack(alignment: .bottom) {
                    PDFSurface(session: session, color: canvas, gap: gap, widthPreference: width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if session.loading { VStack(spacing: 14) { ProgressView(); Text(tr("Loading paper…")).foregroundColor(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(canvasColor) }
                    if let failure = session.failure { EmptyPage(title: tr("Unable to open paper"), detail: failure, icon: "doc.badge.ellipsis").background(canvasColor) }
                }.background(canvasColor)
                if session.showInspector { Divider() }
                inspector.frame(width: session.showInspector ? 264 : 0).opacity(session.showInspector ? 1 : 0).clipped().accessibilityHidden(!session.showInspector).allowsHitTesting(session.showInspector)
            }
            if showProgress, session.pageCount > 0 {
                Divider()
                HStack { Text(pageLabel("\(session.page + 1) / \(session.pageCount)")); Text(tr("·")); Text("\(session.progress)%"); Spacer(); if store.database.objects.first(where: { $0.id == session.paperID })?.sources.contains(where: { $0.provider == "local-document" }) == true { Text(tr("Word / text reading edition")).help(tr("Word reading edition · page numbers refer to this preview")) }; if store.pendingSaves > 0 { Text(tr("Saving…")) } }.font(.system(size: 10)).foregroundColor(.secondary).monospacedDigit().padding(.horizontal, 20).padding(.vertical, 7).background(chrome)
            }
        }.background(chrome)
        .onAppear {
            configureSelectionMenu()
            session.reduceMotion = reduceMotion
            if UserDefaults.standard.object(forKey: "reader.autoProject") as? Bool != false { projectID = store.database.objects.first { $0.id == session.paperID }?.projects.first }
        }
        .onDisappear { session.pdfView.selectionMenu = nil }
        .onChange(of: selectionToolbar) { _ in configureSelectionMenu() }
        .onChange(of: interfaceLanguage) { _ in configureSelectionMenu() }
        .onChange(of: reduceMotion) { session.reduceMotion = $0 }
        .onChange(of: session.showSearch) { if $0 { searchFocused = true } }
        .popover(item: $action, arrowEdge: .bottom) { action in ReaderSelectionEditor(session: session, action: action, initialProject: projectID, onSavedProject: { projectID = $0 }) }
    }
    func configureSelectionMenu() {
        session.pdfView.selectionMenu = {
            session.selectionChanged()
            guard let selection = session.selection, selectionToolbar else { return nil }
            return ReaderContextMenu.make([
                (tr("Highlight"), { highlight(selection) }),
                (tr("Note"), { action = .init(kind: .note, selection: selection) }),
                (tr("Evidence"), { action = .init(kind: .evidence, selection: selection) }),
                (tr("Claim"), { action = .init(kind: .claim, selection: selection) }),
                (tr("Copy"), { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selection.quote, forType: .string) })
            ])
        }
    }
    var chrome: Color { appearance == "comfort" ? Color(red: 0.962, green: 0.953, blue: 0.926) : Palette.paper(scheme) }
    var canvas: NSColor { appearance == "comfort" ? NSColor(calibratedRed: 0.949, green: 0.938, blue: 0.911, alpha: 1) : scheme == .dark ? NSColor(calibratedWhite: 0.13, alpha: 1) : NSColor(calibratedRed: 0.96, green: 0.955, blue: 0.94, alpha: 1) }
    var canvasColor: Color { Color(nsColor: canvas) }
    var toolbar: some View {
        HStack(spacing: 18) {
            tool("Back to Library", "arrow.left") { store.closeReader() }
            if !session.focus { tool("Toggle outline", "sidebar.left", selected: session.showOutline) { panel { session.showOutline.toggle() } } }
            readerTitle
            tool("Search PDF (⌘F)", "magnifyingglass", selected: session.showSearch) { panel { session.showSearch.toggle() }; searchFocused = session.showSearch }
            if let selection = session.selection { tool("Highlight selection", "highlighter") { highlight(selection) } }
            tool("Add note", "square.and.pencil") { action = .init(kind: .note, selection: session.selection ?? .init(quote: "", page: String(session.page + 1), locations: [])) }
            HStack(spacing: 3) {
                tool("Zoom Out", "minus.magnifyingglass") { session.zoom(1 / 1.15) }
                tool("Zoom In", "plus.magnifyingglass") { session.zoom(1.15) }
            }.disabled(!session.canNavigate)
            if !session.focus {
                Menu { if let original = store.database.objects.first(where: { $0.id == session.paperID })?.sources.first(where: { $0.provider == "local-document" })?.url { Button(tr("Open original Word / text document")) { NSWorkspace.shared.open(original) }; Text(tr("Word reading edition · page numbers refer to this preview")); Divider() }; Button(tr("Fit to Width")) { session.fit() }.disabled(!session.canNavigate); Divider(); Button(tr("Mark as Read")) { store.markRead(session.paperID) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22).help(tr("Zoom and reading progress"))
                tool("Toggle research inspector", "sidebar.right", selected: session.showInspector) { panel { session.showInspector.toggle() } }
            }
            tool(session.focus ? "Exit Focus (⇧⌘F)" : "Focus Mode (⇧⌘F)", session.focus ? "arrow.down.right.and.arrow.up.left" : "viewfinder") { panel { session.toggleFocus() } }
        }.padding(.horizontal, 24).frame(height: 58)
    }
    var versionLabel: String? {
        guard let source = session.fullTextSource, let raw = source.metadata["paperVersion"] else { return nil }
        let version = tr((PaperVersion(rawValue: raw) ?? .unknown).title)
        let access = tr(source.metadata["accessType"] == "openAccess" ? "Open Access" : "Local")
        return [version, access, source.metadata["fullTextProvider"] ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var readerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if let label = versionLabel { Text(label).font(.system(size: 10)).foregroundColor(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func tool(_ title: String, _ icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(AcaButtonStyle(inset: 0, selected: selected)).help(tr(title)).accessibilityLabel(tr(title)) }
    func panel(_ action: () -> Void) { withAnimation(AcaMotion.panels(reduced: reduceMotion), action) }
    func highlight(_ selection: ReaderSelection) {
        let item = ReaderHighlight(paperID: session.paperID, documentID: session.documentID, quote: selection.quote, locations: selection.locations)
        if store.change({ $0.highlights = ($0.highlights ?? []) + [item] }) { session.applyHighlights([item]) }
    }
    var outlinePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(tr("Navigation"), selection: $outlineTab) { Text(tr("Outline")).tag("Outline"); Text(tr("Pages")).tag("Pages"); Text(tr("Figures")).tag("Figures") }.labelsHidden().padding(.horizontal, 12).padding(.top, 16)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if outlineTab == "Pages" {
                        ForEach(0..<session.pageCount, id: \.self) { index in
                            Button { session.go(page: index) } label: { VStack(spacing: 6) { ReaderThumbnail(pipeline: session.thumbnails, page: index); Text(pageLabel(String(index + 1))) }.frame(maxWidth: .infinity).font(.caption).padding(9).background(session.page == index ? Palette.accent.opacity(0.14) : .clear) }.buttonStyle(AcaButtonStyle(inset: 0))
                        }
                    } else {
                        let entries = session.outline.filter { outlineTab != "Figures" || $0.title.range(of: #"(?i)^(fig(ure)?\.?\s|图)"#, options: .regularExpression) != nil }
                        if entries.isEmpty { Text(tr(outlineTab == "Figures" ? "No figure bookmarks" : "No outline")).font(.caption).foregroundColor(.secondary).padding(12) }
                        ForEach(entries) { item in Button { session.go(page: item.page) } label: { Text(item.title).font(.caption).multilineTextAlignment(.leading).padding(.leading, CGFloat(max(0, item.depth)) * 8).padding(9).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(AcaButtonStyle(inset: 0)) }
                    }
                }.padding(.horizontal, 8)
            }
        }.frame(maxHeight: .infinity).background(chrome)
    }
    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(tr("Research")).font(.system(size: 20, design: .serif))
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(text: "Project")
                    Picker(tr("Project"), selection: $projectID) { Text(tr("Choose project")).tag(nil as UUID?); ForEach(store.database.projects) { Text($0.title).tag(Optional($0.id)) } }.labelsHidden()
                    if store.database.projects.isEmpty { Button(tr("Create Project…")) { store.sheet = .project } }
                }
                if let projectID = projectID {
                    let claims = store.database.claims.filter { $0.projectID == projectID }
                    let evidence = store.database.evidence.filter { $0.paperID == session.paperID && $0.projectID == projectID }
                    SectionCaption(text: tr("Research Marks") + " · \(claims.count)")
                    ForEach(claims) { claim in ClaimDropRow(claim: claim) }
                    SectionCaption(text: tr("Evidence") + " · \(evidence.count)")
                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 6) { Text(item.quote.isEmpty ? item.note : item.quote).lineLimit(5); Text(pageLabel(item.page) + " · " + tr(item.relationship.rawValue.capitalized)).foregroundColor(.secondary).font(.system(size: 10)) }.font(.caption).padding(.vertical, 4).onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                    }
                }
                let notes = store.database.notes.filter { $0.paperID == session.paperID }
                SectionCaption(text: tr("Notes") + " · \(notes.count)")
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        if let source = note.sourceStatement, !source.isEmpty { Text(source).font(.caption).foregroundColor(.secondary).lineLimit(3) }
                        Text(note.text).font(.caption).textSelection(.enabled)
                        if let page = note.page { Button(pageLabel(page)) { if let number = Int(page.components(separatedBy: "–").first ?? "") { session.go(page: max(0, number - 1)) } }.buttonStyle(.link).font(.system(size: 10)) }
                    }
                }
            }.padding(24).frame(width: 264, alignment: .leading)
        }.background(chrome)
    }
}
struct PDFSurface: NSViewRepresentable {
    var session: ReaderSession; var color: NSColor; var gap: String; var widthPreference: String
    func makeNSView(context: Context) -> ReaderViewport { ReaderViewport(session: session) }
    func updateNSView(_ host: ReaderViewport, context: Context) {
        let view = session.pdfView
        if view.backgroundColor != color { view.backgroundColor = color }
        let margin: CGFloat = gap == "small" ? 3 : gap == "large" ? 18 : 9
        if view.pageBreakMargins.top != margin {
            let position = session.capture(); view.pageBreakMargins = NSEdgeInsets(top: margin, left: 8, bottom: margin, right: 8)
            session.layoutViewport(anchor: position)
        }
        session.setWidthPreference(widthPreference)
    }
}
struct ClaimDropRow: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    var claim: Claim
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { Text(tr(claim.researchType.title)).font(.system(size: 10)).foregroundColor(.secondary); Text(claim.text).font(.caption); Text(trf("%d evidence", claim.evidence.count)).font(.system(size: 10)).foregroundColor(.secondary) }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Palette.accent.opacity(targeted ? 0.14 : 0.035))
            .animation(AcaMotion.feedback(reduced: reduceMotion), value: targeted)
            .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    guard let value = value, let id = UUID(uuidString: value) else { return }
                    DispatchQueue.main.async { store.change { try $0.attachEvidence(id, to: claim.id) } }
                }; return true
            }
    }
}
enum SelectionKind: String { case evidence = "Evidence", claim = "Claim", note = "Note" }
struct SelectionAction: Identifiable { let id = UUID(); var kind: SelectionKind; var selection: ReaderSelection }
struct ReaderSelectionEditor: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    let session: ReaderSession; let action: SelectionAction; let initialProject: UUID?
    var onSavedProject: (UUID) -> Void = { _ in }
    @State private var projectID: UUID?
    @State private var claimID: UUID?
    @State private var text = ""
    @State private var relationship = EvidenceRelationship.background
    @State private var createClaim = false
    @State private var newClaimText = ""
    var valid: Bool { action.kind == .note ? !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : projectID != nil && (action.kind != .claim || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (!createClaim || !newClaimText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        EditorFrame(title: tr("Add " + action.kind.rawValue), saveTitle: tr("Add " + action.kind.rawValue), valid: valid, save: save) {
            if !action.selection.quote.isEmpty {
                Text(tr("Source statement") + " · " + pageLabel(action.selection.page)).font(.caption).foregroundColor(.secondary)
                ScrollView { Text(action.selection.quote).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 115)
            }
            if action.kind != .note {
                Picker(tr("Project"), selection: $projectID) { Text(tr("Select project")).tag(nil as UUID?); ForEach(store.database.projects) { Text($0.title).tag(Optional($0.id)) } }.onChange(of: projectID) { _ in claimID = nil }
                if store.database.projects.isEmpty { Text(tr("Create a project from Library → Projects before collecting evidence.")).font(.caption).foregroundColor(.secondary) }
            }
            if action.kind == .evidence {
                Toggle(tr("Create New Claim"), isOn: $createClaim)
                if createClaim { TextField(tr("My Claim · in your own words"), text: $newClaimText).textFieldStyle(.roundedBorder) }
                else { markPicker }
                Picker(tr("Relationship"), selection: $relationship) { ForEach(EvidenceRelationship.selectable, id: \.self) { Text(tr($0.rawValue.capitalized)).tag($0) } }
            }
            Text(tr(action.kind == .claim ? "My Claim · in your own words" : action.kind == .note ? "My Note" : "Note (optional)")).font(.caption).foregroundColor(.secondary)
            TextEditor(text: $text).frame(height: 90).border(Color.secondary.opacity(0.2))
        }.onAppear { projectID = initialProject ?? (UserDefaults.standard.object(forKey: "reader.autoProject") as? Bool != false ? store.database.objects.first { $0.id == session.paperID }?.projects.first : nil) }
    }
    var availableMarks: [Claim] { store.database.claims.filter { $0.projectID == projectID && $0.markStatus != "deleted" } }
    func markLabel(_ claim: Claim) -> String {
        tr(claim.researchType.title) + " · " + claim.text
    }
    var markPicker: some View {
        Picker(tr("Related research mark"), selection: $claimID) {
            Text(tr("Attach later")).tag(nil as UUID?)
            ForEach(availableMarks) { claim in Text(markLabel(claim)).tag(Optional(claim.id)) }
        }
    }
    func save() {
        if store.change({ db in
            if action.kind == .note {
                var note = ResearchNote(paperID: session.paperID, text: text); note.page = action.selection.page; note.sourceStatement = action.selection.quote; db.notes.append(note)
            } else if let projectID = projectID {
                var target = claimID
                if action.kind == .claim || createClaim { let claim = Claim(projectID: projectID, text: action.kind == .claim ? text : newClaimText); db.claims.append(claim); target = claim.id }
                var evidence = Evidence(paperID: session.paperID, page: action.selection.page, quote: action.selection.quote, note: action.kind == .evidence ? text : "", relationship: relationship)
                evidence.documentID = session.documentID; evidence.locations = action.selection.locations
                try db.saveEvidence(evidence, projectID: projectID, claimID: target)
            }
        }) { if action.kind != .note, let projectID = projectID { onSavedProject(projectID) }; dismiss() }
    }
}

struct ReaderThumbnail: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    let pipeline: ReaderThumbnails?; let page: Int
    @State private var image: NSImage?
    var body: some View {
        Group { if let image = image { Image(nsImage: image).resizable().scaledToFit() } else { Rectangle().fill(Color.secondary.opacity(0.08)).overlay(Image(systemName: "doc").foregroundColor(.secondary)) } }.frame(width: 116, height: 155).onAppear { pipeline?.request(page) { image = $0 } }.onDisappear { image = nil }
    }
}
