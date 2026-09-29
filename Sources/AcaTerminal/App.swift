import SwiftUI
import AppKit
import AcaCore

@main
struct AcaTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = WorkspaceStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("AcaTerminal", id: MainWindowLifecycle.sceneID) {
            ShellView().environmentObject(store).environment(\.locale, L10n.locale)
                .preferredColorScheme(appearance == "dark" ? .dark : ["light", "comfort"].contains(appearance) ? .light : nil)
                .frame(minWidth: 940, minHeight: 650)
                .background(MainWindowRegistration(lifecycle: delegate.windows).frame(width: 0, height: 0))
                .onOpenURL { store.handleResearchURL($0) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshAcaTex() }
                .onAppear { delegate.store = store; delegate.windows.onClose = { store.reader?.saveNow() }; store.presentMainWindow = { delegate.windows.restore() } }
        }.defaultSize(width: 1180, height: 790)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("About AcaTerminal…")) { ApplicationVersion.showAbout() }
            }
            CommandGroup(replacing: .newItem) {
                Button(tr("Import documents…")) { store.chooseDocuments(projectID: store.destination == .projects ? store.selectedProject : nil) }.keyboardShortcut("o").disabled(!store.ready || store.busy)
                Button(tr("Add metadata only…")) { store.sheet = .paper }.keyboardShortcut("n")
                Button(tr("New Project…")) { store.sheet = .project }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button(tr("New Submission…")) { store.sheet = .submission }
            }
            CommandMenu(tr("Reader")) {
                if let reader = store.reader {
                    ReaderMenuItems(reader: reader, close: store.closeReader)
                } else {
                    Button(tr("Find in PDF")) {}.keyboardShortcut("f").disabled(true)
                    Button(tr("Zoom In")) {}.keyboardShortcut("+").disabled(true)
                    Button(tr("Zoom Out")) {}.keyboardShortcut("-").disabled(true)
                    Button(tr("Fit to Width")) {}.keyboardShortcut("0").disabled(true)
                    Button(tr("Toggle Focus Mode")) {}.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(true)
                    Button(tr("Close Reader")) {}.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(true)
                }
            }
            CommandGroup(replacing: .help) {
                Button(tr("Privacy & Data…")) { store.showInformation = true }
                Button(tr("License…")) { ApplicationVersion.openLicense() }
            }
            SidebarCommands()
        }
        Settings { PreferencesView().environmentObject(store).environment(\.locale, L10n.locale).preferredColorScheme(appearance == "dark" ? .dark : ["light", "comfort"].contains(appearance) ? .light : nil).frame(width: 760, height: 740) }
    }
}
