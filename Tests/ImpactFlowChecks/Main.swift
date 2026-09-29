import AppKit
import CryptoKit
import AcaCore

@main struct ImpactFlowChecks {
    struct Failure: Error { let message: String }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }
        throw Failure(message: "Timed out")
    }
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }; count += 1; print("PASS \(message)")
    }
    @MainActor static func main() async {
        do {
            guard let directory = ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"], !FileManager.default.fileExists(atPath: directory), CommandLine.arguments.count == 2 else { throw Failure(message: "Requires a NEW isolated data directory and a local PDF") }
            _ = NSApplication.shared
            let url = URL(fileURLWithPath: CommandLine.arguments[1]), original = SHA256.hash(data: try Data(contentsOf: url))
            let store = WorkspaceStore(); try await wait { store.ready }
            try check(store.database.objects.isEmpty, "Isolated workspace opens without sample data")
            let cited = ResearchObject(title: "Flow test cited work")
            var citing = ResearchObject(title: "Flow test citing work")
            citing.sources = [.init(provider: "local-pdf", externalID: "flow", url: url, metadata: ["paperVersion": "accepted", "accessType": "openAccess", "fullTextProvider": "Flow fixture repository"])]
            var event = CitationEvent(citedWorkID: cited.id, work: .init(id: "flow-citer", object: citing), provider: "openalex", detectedAt: Date())
            event.notificationClaimedAt = Date()
            try check(store.change { $0.objects.append(cited); $0.citationEvents = [event] }, "Citation event enters existing workspace persistence")
            var presented = false; store.presentMainWindow = { presented = true }
            store.notifications.onCitation?(event.id)
            try check(presented && store.destination == .impact && store.selectedCitationID == event.id && store.database.citationEvents?.first?.seen == true, "Notification callback routes to citation detail and marks seen")
            let work = store.importCitingWork(event)!
            _ = store.importCitingWork(event)
            try check(store.database.objects.count == 2, "Citation detail import is idempotent")
            store.openReader(work); try await wait { store.reader?.loading == false }
            try check(store.reader?.failure == nil && (store.reader?.pageCount ?? 0) > 0, "Citation detail opens a real PDF in existing Reader")
            try check(store.reader?.fullTextSource?.metadata["paperVersion"] == "accepted", "Reader retains selected version provenance")
            store.reader?.go(page: 1); store.reader?.saveNow(); store.closeReader()
            try check(store.database.readingPosition(for: work.id) != nil, "Citation reading position uses existing persistence")
            store.openReader(cited)
            try check(store.fullTextObject?.id == cited.id && store.reader == nil, "Metadata-only citation routes to full-text resolver")
            guard await store.savedBarrier() else { throw Failure(message: "Save failed") }
            let reopened = WorkspaceStore(); try await wait { reopened.ready }
            try check(reopened.database.citationEvents?.first?.seen == true && reopened.database.objects.contains { $0.id == work.id } && reopened.database.readingPosition(for: work.id) != nil, "Citation detail state, imported work and reading position survive restart")
            let after = SHA256.hash(data: try Data(contentsOf: url))
            try check(after == original, "Citation Reader leaves original PDF bytes unchanged")
            print("\(count) impact integration assertions passed. OS banner delivery is not exercised.")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
