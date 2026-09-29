import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AcaCore
import AcaConnectors

extension WorkspaceStore {
    func chooseDocuments(projectID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentImport.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importDocuments(panel.urls, projectID: projectID) }
    }
    func importLocalPDF(_ url: URL) { importDocuments([url]) }
    func importDocuments(_ urls: [URL], projectID: UUID? = nil) {
        guard ready, !busy else { return }
        busy = true
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Documents", isDirectory: true)
        Task {
            defer { busy = false }
            var first: ResearchObject?
            var failures: [String] = []
            for url in urls {
                if var existing = database.objects.first(where: { $0.sources.contains { $0.metadata["originalPath"] == url.standardizedFileURL.path || $0.url == url } }) {
                    if let projectID = projectID, !existing.projects.contains(projectID) {
                        existing.projects.append(projectID)
                        let updated = existing
                        _ = change { db in if let i = db.objects.firstIndex(where: { $0.id == updated.id }) { db.objects[i] = updated } }
                    }
                    first = first ?? existing; continue
                }
                do {
                    var item = try await Task.detached(priority: .userInitiated) { try DocumentImport.prepare(url, directory: directory, id: UUID()) }.value
                    if let projectID = projectID { item.projects = [projectID] }
                    if change({ $0.objects.append(item) }) { first = first ?? item }
                } catch { failures.append(url.lastPathComponent + ": " + tr(error.localizedDescription)) }
            }
            if let paper = first { selectedPaper = paper.id; destination = .library; openReader(paper) }
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    func openReader(_ paper: ResearchObject, sourceID: String? = nil) {
        if pendingEvidence?.paperID != paper.id { pendingEvidence = nil }
        if !paper.sources.contains(where: { ($0.provider == "local-pdf" && $0.url?.isFileURL == true && FileManager.default.fileExists(atPath: $0.url!.path)) || $0.provider == "zotero-pdf" }) { fullTextObject = paper; return }
        reader?.close()
        let requestedSource = sourceID.flatMap { id in paper.sources.first { $0.id == id } }
        let localSource = (requestedSource?.provider == "local-pdf" ? requestedSource : nil) ?? paper.sources.first { $0.provider == "local-pdf" && $0.url?.isFileURL == true && FileManager.default.fileExists(atPath: $0.url!.path) }
        let session = ReaderSession(paper: paper)
        session.fullTextSource = localSource
        session.onReady = { [weak self, weak session] in
            guard let self = self, let session = session, self.reader === session, let evidence = self.pendingEvidence, evidence.paperID == paper.id else { return }
            self.pendingEvidence = nil
            if !session.reveal(evidence) { self.message = "Opened the source page. The exact passage could not be located in this document version." }
        }
        withAnimation(AcaMotion.transition(reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { reader = session }
        session.onPosition = { [weak self] position in
            self?.change { db in db.savePosition(position); if let index = db.objects.firstIndex(where: { $0.id == position.paperID }) { db.objects[index].lastReadAt = Date() } }
        }
        let position = database.readingPosition(for: paper.id), highlights = database.highlights ?? []
        if requestedSource?.provider != "zotero-pdf", let url = localSource?.url, url.isFileURL {
            session.load(url: url, position: position, highlights: highlights)
        } else if let source = (requestedSource?.provider == "zotero-pdf" ? requestedSource : nil) ?? paper.sources.first(where: { $0.provider == "zotero-pdf" }) {
            Task {
                do {
                    let key = source.externalID.hasPrefix("web:") ? try credentials.read("zotero.apiKey") : nil
                    let directory = databaseURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
                    let url = try await ZoteroAttachment.download(source: source, apiKey: key, directory: directory)
                    guard reader === session else { return }
                    session.load(url: url, position: position, highlights: highlights)
                } catch { session.loading = false; session.failure = error.localizedDescription }
            }
        } else { session.loading = false; session.failure = "This record has metadata only. Attach a local PDF from the paper’s menu, or import an available Zotero PDF attachment." }
    }
    func openEvidence(_ evidence: Evidence) {
        guard let paper = database.objects.first(where: { $0.id == evidence.paperID }) else { return }
        if let reader = reader, reader.paperID == paper.id, !reader.loading {
            if !reader.reveal(evidence) { message = "Opened the source page. The exact passage could not be located in this document version." }
        } else { pendingEvidence = evidence; openReader(paper) }
    }
    func closeReader() { reader?.close(); withAnimation(AcaMotion.transition(reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) { reader = nil; destination = .library } }
    func markRead(_ paperID: UUID) {
        reader?.saveNow()
        change { db in
            var position = db.readingPosition(for: paperID) ?? ReadingPosition(paperID: paperID, documentID: "", markedRead: true)
            position.markedRead = true; db.savePosition(position)
        }
        if reader?.paperID == paperID { reader?.setRead() }
    }
    func exportRecovery(completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "AcaTerminal-research-recovery.json"
        guard panel.runModal() == .OK, let url = panel.url else { completion?(false); return }
        let snapshot = database
        Task {
            do { try await Task.detached(priority: .userInitiated) { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(snapshot).write(to: url, options: .atomic) }.value; message = "Research snapshot exported, including unsaved edits."; completion?(true) }
            catch { self.error = error.localizedDescription; completion?(false) }
        }
    }
}
