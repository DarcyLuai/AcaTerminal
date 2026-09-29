import SwiftUI
import AppKit
import AcaCore

@main struct LifecycleChecks {
    struct Failure: Error { let message: String }
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws { guard condition() else { throw Failure(message: message) }; count += 1; print("PASS \(message)") }
    @MainActor static func pause() async throws { try await Task.sleep(nanoseconds: 350_000_000) }
    @MainActor static func main() {
        let app = NSApplication.shared
        Task { @MainActor in await run() }
        app.run()
    }
    @MainActor static func run() async {
        do {
            guard let directory = ProcessInfo.processInfo.environment["ACATERMINAL_DATA_DIR"], !FileManager.default.fileExists(atPath: directory), CommandLine.arguments.count == 2 else { throw Failure(message: "Requires NEW isolated data path and test PDF") }
            let app = NSApplication.shared; app.setActivationPolicy(.regular)
            let store = WorkspaceStore(); for _ in 0..<100 where !store.ready { try await pause() }
            try check(store.ready && app.activationPolicy() == .regular, "Regular app and isolated database are ready")
            let delegate = AppDelegate(); delegate.store = store
            var windows: [NSWindow] = []; var created = 0
            func create() {
                let w = NSWindow(contentRect: NSRect(x: 40, y: 60, width: 1000, height: 700), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false; w.contentView = NSHostingView(rootView: ShellView().environmentObject(store)); windows.append(w); created += 1
                delegate.windows.register(w); w.makeKeyAndOrderFront(nil)
            }
            delegate.windows.openScene = { create() }; create(); app.activate(ignoringOtherApps: true); try await pause()
            let original = windows[0]
            func reopen(_ flag: Bool = false) { _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: flag) }
            func restored() -> Bool {
                let ok = delegate.windows.window === original && !original.isMiniaturized && original.isVisible && original.isKeyWindow && created == 1
                if !ok { print("STATE mini=\(original.isMiniaturized) visible=\(original.isVisible) key=\(original.isKeyWindow) active=\(app.isActive) created=\(created)") }; return ok
            }
            original.standardWindowButton(.miniaturizeButton)?.performClick(nil); try await pause(); reopen(); try await pause()
            try check(restored(), "Yellow-button minimize restores same key window")
            original.performMiniaturize(nil); try await pause(); reopen(true); try await pause()
            try check(restored(), "Standard performMiniaturize (Command-M action) restores same window")
            var paper = ResearchObject(title: "Lifecycle test PDF"); paper.sources = [.init(provider:"local-pdf",externalID:"lifecycle",url:URL(fileURLWithPath:CommandLine.arguments[1]))]
            _ = store.change { $0.objects.append(paper) }; store.openReader(paper)
            for _ in 0..<100 where store.reader?.loading != false { try await pause() }
            let reader = store.reader!; let document = reader.pdfView.document
            original.miniaturize(nil); try await pause(); reopen(); try await pause()
            try check(restored() && store.reader === reader && reader.pdfView.document === document, "Reader and PDF instance survive reopen")
            reader.showSearch = true; reader.query = "deterrence"; original.miniaturize(nil); try await pause(); reopen(); try await pause()
            try check(restored() && reader.showSearch && reader.query == "deterrence", "PDF search survives reopen")
            reader.toggleFocus(); original.miniaturize(nil); try await pause(); reopen(); try await pause()
            try check(restored() && reader.focus, "Focus state survives reopen")
            let sheet = NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:150),styleMask:[.titled],backing:.buffered,defer:false);sheet.isReleasedWhenClosed=false
            original.beginSheet(sheet, completionHandler: { _ in }); original.endSheet(sheet);sheet.orderOut(nil);original.miniaturize(nil);try await pause();reopen();try await pause()
            try check(restored(), "Closed sheet does not block reopen")
            original.appearance = NSAppearance(named:.darkAqua);original.miniaturize(nil);try await pause();reopen();try await pause();try check(restored(), "Dark appearance restores")
            original.appearance = NSAppearance(named:.aqua);original.backgroundColor = NSColor(calibratedRed:0.95,green:0.94,blue:0.91,alpha:1);original.miniaturize(nil);try await pause();reopen();try await pause();try check(restored(), "Eye Comfort surfaces restore")
            for _ in 0..<20 { original.miniaturize(nil);try await pause();reopen();try await pause();guard restored() else { throw Failure(message:"20-cycle restore failed") } }
            try check(restored(), "20 consecutive minimize/reopen cycles: zero duplicate windows")
            _ = store.change { $0.notes.append(.init(paperID:paper.id,text:"Background save survives restoration")) }
            let pending = store.pendingSaves > 0;original.miniaturize(nil);reopen();guard await store.savedBarrier() else { throw Failure(message:"Save barrier") };try await pause()
            try check(pending && restored() && !store.saveFailed, "Reopen during background save preserves durable data")
            original.close();try await pause();try check(delegate.windows.window == nil, "Closed window is deregistered")
            reopen();reopen();try await pause();try check(created == 2 && delegate.windows.window === windows[1] && store.reader === reader && reader.focus, "Closed main scene recreates once with existing Reader state")
            let settings = NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:150),styleMask:[.titled],backing:.buffered,defer:false);settings.makeKeyAndOrderFront(nil);reopen(true);try await pause()
            try check(windows[1].isKeyWindow && created == 2, "Visible settings window cannot steal main-window restoration")
            app.hide(nil); try await pause(); reopen(); try await pause()
            try check(!app.isHidden && delegate.windows.window === windows[1] && windows[1].isVisible && !windows[1].isMiniaturized, "Hidden app restores original visible window")
            print("OBSERVATION hide/reopen key=\(windows[1].isKeyWindow) active=\(app.isActive). macOS cooperative activation may deny a synthetic background callback; physical Dock activation remains a UI acceptance boundary.")
            var canQuit = false; store.prepareToQuit { canQuit = $0 };for _ in 0..<50 where !canQuit { try await pause() };try check(canQuit, "Quit still drains the database save queue")
            print("\(count) lifecycle assertions passed; Dock handler invoked directly against real AppKit windows."); exit(0)
        } catch { print("FAIL \(error)");exit(1) }
    }
}
