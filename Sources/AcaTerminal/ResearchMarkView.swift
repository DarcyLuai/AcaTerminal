import SwiftUI
import AcaCore

struct AcaTexProjectControls: View {
    @EnvironmentObject var store: WorkspaceStore
    var projectID: UUID
    var body: some View {
        Menu {
            Button(tr("Connect AcaTex Project…")) { store.chooseAcaTexProject(projectID) }
            ForEach((store.database.acaTexConnections ?? []).filter { $0.projectID == projectID }) { connection in
                Button(tr("Refresh AcaTex Marks")) { store.refreshAcaTex(connection.id) }.disabled(store.markRefreshing.contains(connection.id))
            }
            if store.database.acaTexConnections?.contains(where: { $0.projectID == projectID }) == true {
                Button(tr("Export Research Marks…")) { store.sendMarksToAcaTex(projectID, claimIDs: Set(store.database.claims.filter { $0.projectID == projectID }.map(\.id))) }
            }
        } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }.menuStyle(.borderlessButton).fixedSize().frame(width: 30, height: 30).disabled(store.markConnecting).help(tr("Project settings"))
    }
}
struct AcaTexConnectionStatus: View {
    @EnvironmentObject var store: WorkspaceStore
    var projectID: UUID
    var body: some View {
        ForEach((store.database.acaTexConnections ?? []).filter { $0.projectID == projectID }) { connection in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AcaTex · " + connection.fileURL.deletingPathExtension().lastPathComponent).font(.caption).foregroundColor(.secondary)
                    if store.markErrors[connection.id] != nil { Text(tr("Source unavailable · saved research remains here")).font(.caption).foregroundColor(.secondary) }
                }
                Spacer()
                if store.markRefreshing.contains(connection.id) { ProgressView().controlSize(.small) }
                else { Button { store.refreshAcaTex(connection.id) } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }.buttonStyle(AcaButtonStyle(inset: 0)).help(tr("Refresh AcaTex Marks")).accessibilityLabel(tr("Refresh AcaTex Marks")) }
            }
        }
    }
}
struct ResearchMarkRow: View {
    @EnvironmentObject var store: WorkspaceStore
    var claim: Claim
    @State private var edit = false
    @State private var conflict = false
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(claim.text).font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
                    if let binding = store.database.binding(for: claim.id) {
                        HStack(spacing: 8) {
                            Text(tr(binding.remote.sourceApp == "AcaTerminal" ? "From AcaTerminal" : "From AcaTex"))
                            if let state = store.database.syncStatus(for: claim.id), state != .synced {
                                Text("·").accessibilityHidden(true)
                                Text(tr(state.rawValue))
                            }
                        }.font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Menu {
                    Button(tr("Edit mark…")) { text = claim.text; edit = true }
                    if store.database.binding(for: claim.id) != nil {
                        Button(tr(store.openingAcaTexMark == claim.id ? "Opening AcaTex…" : "Open in AcaTex")) { store.openAcaTexMark(claim.id) }
                            .disabled(store.openingAcaTexMark != nil)
                    }
                    if store.database.syncStatus(for: claim.id) == .conflict { Button(tr("Review conflict…")) { conflict = true } }
                    Button(tr("Find related papers")) { store.discoveryMarkID = claim.id; store.projectTab = "Discover" }
                    Button(tr("Export Research Mark…")) { store.sendMarksToAcaTex(claim.projectID, claimIDs: [claim.id]) }.disabled(store.markConnecting)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().frame(width: 28, height: 28).help(tr("More actions"))
            }
            ForEach(store.database.evidence.filter { claim.evidence.contains($0.id) }) { item in
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr(store.database.relationship(evidenceID: item.id, claimID: claim.id).rawValue.capitalized) + " · " + pageLabel(item.page)).font(.caption).foregroundColor(.secondary)
                    Text(item.quote.isEmpty ? item.note : "“\(item.quote)”").font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    if let paper = store.database.objects.first(where: { $0.id == item.paperID }) { Button(paper.title) { store.openEvidence(item) }.buttonStyle(.link).font(.caption) }
                }.padding(.leading, 16).overlay(alignment: .leading) { Rectangle().fill(Palette.accent.opacity(0.35)).frame(width: 2) }
            }
        }.padding(.vertical, 10)
        .sheet(isPresented: $edit) { EditorFrame(title: tr("Edit mark"), valid: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: { store.editMark(claim.id, text: text); edit = false }) { TextEditor(text: $text).frame(height: 180); Text(tr("Changes are saved in AcaTerminal. You can export them without changing the source document.")).font(.caption).foregroundColor(.secondary) } }
        .sheet(isPresented: $conflict) { ResearchConflictView(claim: claim) }
    }
}
struct ResearchConflictView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var claim: Claim
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(tr("Review changes")).font(.system(size: 25, design: .serif))
            Text(tr("Both versions are retained. Choose the version to use in AcaTerminal; this does not edit the manuscript.")).font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionCaption(text: "Your version"); Text(store.database.claims.first { $0.id == claim.id }?.text ?? claim.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                    Divider().padding(.vertical, 8); SectionCaption(text: "AcaTex version"); Text(store.database.binding(for: claim.id)?.remote.text ?? "").font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Button(tr("Cancel")) { dismiss() }; Spacer(); Button(tr("Keep AcaTerminal version")) { resolve(false) }; Button(tr("Use AcaTex version")) { resolve(true) } }
        }.padding(32).frame(width: 620, height: 440)
    }
    func resolve(_ remote: Bool) { if store.change({ try $0.resolveMarkConflict(claim.id, useRemote: remote) }) { dismiss() } }
}
