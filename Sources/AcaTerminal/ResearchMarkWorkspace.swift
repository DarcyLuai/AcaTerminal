import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AcaCore
import AcaConnectors

extension WorkspaceStore {
    func chooseAcaTexProject(_ projectID: UUID) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "texflow") ?? .json, UTType(filenameExtension: "acatex") ?? .json, .json]
        panel.message = tr("Choose a saved local AcaTex project. Research marks stay on this Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }; connectAcaTex(projectID: projectID, url: url)
    }
    func connectAcaTex(projectID: UUID, url: URL) {
        guard !markConnecting else { return }; markConnecting = true
        Task {
            defer { markConnecting = false }
            do {
                let exchange = try await Task.detached(priority: .userInitiated) { try AcaTexProjectReader().readProject(at: url) }.value
                guard database.projects.contains(where: { $0.id == projectID }) else { return }
                if let old = database.acaTexConnections?.first(where: { $0.projectID == projectID }), old.documentID != exchange.sourceDocument { throw CoreError.invalid("This project already has a connected AcaTex document. Use a separate project for another manuscript.") }
                if let old = database.acaTexConnections?.first(where: { $0.documentID == exchange.sourceDocument }), old.projectID != projectID { throw CoreError.invalid("This AcaTex document is already connected to another project.") }
                change { db in
                    let connection = db.acaTexConnections?.first { $0.documentID == exchange.sourceDocument } ?? AcaTexConnection(projectID: projectID, documentID: exchange.sourceDocument, fileURL: url)
                    if let i = db.acaTexConnections?.firstIndex(where: { $0.id == connection.id }) { db.acaTexConnections?[i].fileURL = url }
                    else { db.acaTexConnections = (db.acaTexConnections ?? []) + [connection] }
                    try db.ingestMarks(exchange, connectionID: connection.id); try db.validate()
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func refreshAcaTex(_ id: UUID? = nil) {
        guard ready, !saveFailed else { return }
        for connection in database.acaTexConnections ?? [] where id == nil || connection.id == id {
            guard !markRefreshing.contains(connection.id) else { continue }
            markRefreshing.insert(connection.id)
            markTasks[connection.id] = Task {
                defer { markRefreshing.remove(connection.id); markTasks[connection.id] = nil }
                do {
                    let exchange = try await Task.detached(priority: .utility) { try AcaTexProjectReader().readProject(at: connection.fileURL) }.value
                    try Task.checkCancellation()
                    if change({ try $0.ingestMarks(exchange, connectionID: connection.id); try $0.validate() }) { markErrors[connection.id] = nil }
                } catch { if !Task.isCancelled { markErrors[connection.id] = error.localizedDescription } }
            }
        }
    }
    func editMark(_ id: UUID, text: String) {
        change { db in guard let i = db.claims.firstIndex(where: { $0.id == id }) else { return }; db.claims[i].text = text.trimmingCharacters(in: .whitespacesAndNewlines); db.claims[i].updatedAt = Date() }
    }
    func openAcaTexMark(_ claimID: UUID) {
        guard openingAcaTexMark == nil else { return }
        guard let binding = database.binding(for: claimID), let connection = database.acaTexConnections?.first(where: { $0.id == binding.connectionID }) else { return }
        let route = ResearchRoute.acaTex(documentID: connection.documentID, markID: binding.externalID)
        guard let application = AcaTexNavigation.applicationURL(for: route) else {
            NSWorkspace.shared.activateFileViewerSelecting([connection.fileURL])
            message = tr("Install an AcaTex version with Research Bridge support to open this mark directly. The connected project is shown in Finder.")
            return
        }
        openingAcaTexMark = claimID
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        // Target the verified application explicitly: an older copy may own the URL scheme.
        NSWorkspace.shared.open([route], withApplicationAt: application, configuration: configuration) { [weak self] _, failure in
            Task { @MainActor in
                self?.openingAcaTexMark = nil
                if let failure { self?.error = tr("Could not open AcaTex.") + " " + failure.localizedDescription }
            }
        }
    }
    func sendMarksToAcaTex(_ projectID: UUID, claimIDs: Set<UUID>) {
        guard let connection = database.acaTexConnections?.first(where: { $0.projectID == projectID }) else { error = tr("Connect an AcaTex project first."); return }
        do {
            var snapshot = database
            let exchange = try snapshot.exportMarks(connectionID: connection.id, claimIDs: claimIDs)
            let data = try ResearchMarkCodec.encode(exchange)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = connection.fileURL.deletingPathExtension().lastPathComponent + ".acaresearch.json"
            panel.message = tr("Export research marks and evidence links as a local exchange file. Your manuscript is unchanged.")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            guard url.standardizedFileURL != connection.fileURL.standardizedFileURL else { throw CoreError.invalid("Choose an exchange file, not the connected manuscript.") }
            markConnecting = true
            Task {
                defer { markConnecting = false }
                do {
                    try await Task.detached(priority: .utility) { try data.write(to: url, options: .atomic) }.value
                    let sentBindings = (snapshot.markBindings ?? []).filter { claimIDs.contains($0.claimID) }
                    change { db in
                        for sent in sentBindings where db.claims.contains(where: { $0.id == sent.claimID }) {
                            if let i = db.markBindings?.firstIndex(where: { $0.claimID == sent.claimID }) { db.markBindings?[i].lastSent = sent.lastSent }
                            else { db.markBindings = (db.markBindings ?? []) + [sent] }
                        }
                    }
                    message = tr("Research exchange exported. Importing it requires an application that supports this format; the connected manuscript has not been changed.")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    func handleResearchURL(_ url: URL) {
        guard let route = ResearchRoute(url: url) else { error = tr("Unsupported research link."); return }
        guard ready else { pendingResearchURL = url; return }
        switch route {
        case .evidence(let paperID, let evidenceID):
            guard let evidence = database.evidence.first(where: { $0.id == evidenceID && $0.paperID == paperID }) else { error = tr("This evidence is not in the current local workspace."); return }
            presentMainWindow?(); openEvidence(evidence)
        }
    }
}
