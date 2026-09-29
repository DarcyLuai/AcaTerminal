import SwiftUI
import AppKit
import PDFKit
import CryptoKit
import AcaCore

@main struct ReadingSpaceChecks {
    struct Failure: Error { var message: String }
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws { guard try value() else { throw Failure(message: name) }; count += 1; print("PASS " + name) }
    @MainActor static func settle() async throws { try await Task.sleep(nanoseconds: 280_000_000) }
    @MainActor static func wait(_ condition: () -> Bool) async throws { for _ in 0..<120 { if condition() { return }; try await Task.sleep(nanoseconds: 100_000_000) }; throw Failure(message: "Timed out") }
    @MainActor static func main() { Task { @MainActor in await run() }; NSApplication.shared.run() }
    @MainActor static func run() async {
        do {
            guard let directory = ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"], !FileManager.default.fileExists(atPath: directory), CommandLine.arguments.count == 2 else { throw Failure(message: "Requires new isolated workspace and real PDF") }
            let url = URL(fileURLWithPath: CommandLine.arguments[1]), original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let store = WorkspaceStore(); try await wait { store.ready }
            var paper = ResearchObject(title: "Reading space QA"); paper.sources = [.init(provider: "local-pdf", externalID: "reading-space", url: url)]
            _ = store.change { $0.objects = [paper] }; store.openReader(paper)
            let session = store.reader!
            let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 1500, height: 900), styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AcademicReader(session: session).environmentObject(store))
            window.makeKeyAndOrderFront(nil)
            try await wait { !session.loading && (session.viewport?.bounds.width ?? 0) > 1000 }; try await settle()
            let document = session.pdfView.document!, initialWidth = session.pdfView.bounds.width, available = session.viewport!.bounds.width
            print("METRIC initial PDF viewport \(Int(initialWidth)) / available \(Int(available)); physical scale \(session.pdfView.scaleFactor)")
            try check(initialWidth > 860 && abs(initialWidth / available - 0.92) < 0.02, "Initial reading area uses 92% of available width, no fixed 860-point cap")
            session.go(page: 13); try await settle(); let initial = session.capture()!
            session.zoom(1.04); try await settle()
            try check(session.pdfView.bounds.width > initialWidth && session.pdfView.bounds.width < available, "Stage one enlarges actual viewport before using all available space")
            session.zoom(1 / 1.04); try await settle()
            try check(abs(session.pdfView.bounds.width - initialWidth) < 1, "Stage one zoom-out exactly reverses width expansion")
            session.zoom(1.15); try await settle()
            try check(abs(session.pdfView.bounds.width - available) < 1 && session.readingScale > 1, "Crossing boundary fills viewport and spends only remaining magnification on content")
            let fullWidth = session.pdfView.bounds.width, physical = session.pdfView.scaleFactor
            session.pdfView.zoomIn(nil); try await settle()
            try check(abs(session.pdfView.bounds.width - fullWidth) < 1 && session.pdfView.scaleFactor > physical, "PDFKit zoom responder uses stage two in the full viewport")
            session.pdfView.zoomOut(nil); session.zoom(1 / 1.15); try await settle()
            try check(abs(session.pdfView.bounds.width - initialWidth) < 1 && abs(session.readingScale - 0.92) < 0.001, "Zoom reverses continuously across both stages")
            try check(session.capture()?.page == initial.page, "Two-stage transitions retain physical page anchor")
            session.fit(); try await settle()
            try check(session.readingScale == 1 && abs(session.pdfView.bounds.width - available) < 1, "Fit to Width fills usable viewport")
            session.showOutline = true; session.showInspector = true; try await settle()
            let withPanels = session.viewport!.bounds.width
            try check(available - withPanels > 430 && available - withPanels < 460, "Visible outline and inspector reserve their own widths")
            session.zoom(1.4); try await settle()
            try check(abs(session.pdfView.bounds.width - withPanels) < 1 && session.showOutline && session.showInspector, "Content zoom never squeezes or hides visible panels")
            func scrollView(_ view: NSView) -> NSScrollView? { if let scroll = view as? NSScrollView { return scroll }; return view.subviews.compactMap(scrollView).first }
            let scroll = scrollView(session.pdfView)!
            try check(scroll.documentView!.bounds.width > scroll.contentView.bounds.width + 100, "Beyond available width PDFKit exposes a wider scrollable document")
            scroll.contentView.scroll(to: NSPoint(x: max(0, scroll.documentView!.bounds.width - scroll.contentView.bounds.width), y: scroll.contentView.bounds.origin.y)); scroll.reflectScrolledClipView(scroll.contentView)
            try check(scroll.contentView.bounds.origin.x > 50, "Native horizontal scrolling reaches magnified page content")
            session.go(page: 13)
            let selected = document.page(at: 13)!.selection(for: NSRange(location: 0, length: 50))!
            session.pdfView.setCurrentSelection(selected, animate: false); session.selectionChanged()
            let quote = session.selection!.quote, locations = session.selection!.locations
            var evidence = Evidence(paperID: paper.id, page: "14", quote: quote, relationship: .qualifies)
            evidence.documentID = session.documentID; evidence.locations = locations
            try check(session.reveal(evidence), "Evidence navigation resolves the stored passage")
            let destination = session.pdfView.currentDestination!.point
            for _ in 0..<20 { session.layoutViewport() }
            try await settle()
            try check(session.pdfView.currentDestination!.point == destination && session.pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) == quote,
                      "Repeated unchanged layouts do not overwrite explicit evidence navigation")
            session.zoom(1.1); try await settle()
            try check(session.pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) == quote && session.selection?.locations == locations, "Zoom preserves text selection and Evidence coordinates")
            session.toggleFocus(); try await settle()
            try check(session.viewport!.bounds.width > withPanels + 430 && session.pdfView.document === document, "Focus gains available panel space without replacing document")
            session.toggleFocus(); try await settle()
            try check(abs(session.viewport!.bounds.width - withPanels) < 2 && session.showOutline && session.showInspector, "Leaving Focus restores panel widths")
            let anchor = session.capture()!, scale = session.readingScale
            window.setContentSize(NSSize(width: 1150, height: 760)); try await settle()
            try check(session.capture()?.page == anchor.page && abs(session.readingScale - scale) < 0.001, "Window resize preserves physical page and relative reading scale")
            session.pdfView.onMagnification?(1.1); try await settle()
            try check(abs(session.readingScale - scale * 1.1) < 0.001, "Magnification gesture callback shares the same zoom state")
            session.pdfView.onFitWidth?(); try await settle()
            try check(session.readingScale == 1, "Smart magnify uses the same Fit to Width action")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] { window.appearance = NSAppearance(named: appearance); try await settle(); try check(session.pdfView.document === document && session.readingScale == 1, "Appearance \(appearance.rawValue) leaves geometry and document intact") }
            session.pdfView.backgroundColor = NSColor(calibratedRed:0.949,green:0.938,blue:0.911,alpha:1)
            try check(session.pdfView.document === document, "Eye Comfort surface does not recolor original PDF data")
            session.go(page: 24); session.zoom(1.2); try await settle(); session.saveNow()
            let saved = store.database.readingPosition(for: paper.id)!
            try check(saved.readingScale != nil, "New width-relative scale is persisted alongside legacy PDF zoom")
            store.closeReader(); store.openReader(paper); let reopened = store.reader!
            window.contentView = NSHostingView(rootView: AcademicReader(session: reopened).environmentObject(store))
            try await wait { !reopened.loading }; try await settle()
            try check(reopened.capture()?.page == saved.page && abs(reopened.readingScale - CGFloat(saved.readingScale!)) < 0.001, "Reopen restores page and two-stage reading scale")
            var legacy = saved; legacy.readingScale = nil
            reopened.restore(legacy, zoom: true); try await settle()
            try check(abs(reopened.pdfView.scaleFactor - CGFloat(legacy.zoom)) < 0.02 && reopened.capture()?.page == legacy.page, "Old reading records restore physical zoom without a migration")
            try check(SHA256.hash(data: try Data(contentsOf: url)) == SHA256.hash(data: original), "Original PDF bytes unchanged after all reader operations")
            reopened.close(); guard await store.savedBarrier() else { throw Failure(message: "Failed to save") }
            print("\(count) reading-space checks passed. Hardware trackpad gesture event delivery is not simulated."); exit(0)
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
