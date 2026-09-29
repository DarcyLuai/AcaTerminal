import SwiftUI
import AppKit

/// One owner for reopen requests. Never chooses a settings window, panel or reader subview.
@MainActor final class MainWindowLifecycle: NSObject {
    static let sceneID = "main"
    weak var window: NSWindow?
    var openScene: (() -> Void)?
    var onClose: (() -> Void)?
    private var opening = false
    func register(_ candidate: NSWindow) {
        guard window !== candidate else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        window = candidate; opening = false
        candidate.identifier = NSUserInterfaceItemIdentifier(Self.sceneID)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification, object: candidate)
    }
    @objc private func windowClosed(_ notification: Notification) { onClose?(); window = nil; opening = false }
    func restore() { restore(.shared) }
    func restore(_ application: NSApplication) {
        application.unhide(nil)
        if let window = window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.attachedSheet?.makeKeyAndOrderFront(nil)
            application.activate(ignoringOtherApps: true)
        } else if !opening, let openScene = openScene {
            opening = true; openScene()
            application.activate(ignoringOtherApps: true)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
struct MainWindowRegistration: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    let lifecycle: MainWindowLifecycle
    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ view: WindowProbe, context: Context) {
        lifecycle.openScene = { openWindow(id: MainWindowLifecycle.sceneID) }
        view.register = { lifecycle.register($0) }
        if let window = view.window { lifecycle.register(window) }
    }
    final class WindowProbe: NSView {
        var register: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window = window { register?(window) } }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    let windows = MainWindowLifecycle()
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.restore(sender)
        return false // Handled here; prevent a second default window-opening path.
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = store else { return .terminateNow }
        store.prepareToQuit { success in
            if success { sender.reply(toApplicationShouldTerminate: true); return }
            let alert = NSAlert(); alert.messageText = tr("Research changes are not saved")
            alert.informativeText = tr("Keep the app open, or export all research to a recovery file before quitting.")
            alert.addButton(withTitle: tr("Keep Open")); alert.addButton(withTitle: tr("Export and Quit…"))
            if alert.runModal() == .alertSecondButtonReturn { store.exportRecovery { exported in sender.reply(toApplicationShouldTerminate: exported) } }
            else { sender.reply(toApplicationShouldTerminate: false) }
        }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidResignActive(_ notification: Notification) { store?.reader?.saveNow() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
