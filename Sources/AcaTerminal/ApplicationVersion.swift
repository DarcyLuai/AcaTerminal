import SwiftUI
import AppKit

/// Bundle is the single version source for menus, About and information surfaces.
enum ApplicationVersion {
    static var short: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "10" }
    static var display: String { "v" + (short.hasSuffix(".0") ? String(short.dropLast(2)) : short) }
    static var label: String { display + " · " + trf("Build %@", build) }
    @MainActor static func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "AcaTerminal",
            .applicationVersion: display,
            .version: build,
            .credits: NSAttributedString(string: tr("Your research, from idea to impact."))
        ])
    }
    @MainActor static func openLicense() {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
}

struct ReaderMenuItems: View {
    @ObservedObject var reader: ReaderSession
    var close: @MainActor () -> Void
    var body: some View {
        Button(tr("Find in PDF")) { reader.showSearch = true }.keyboardShortcut("f").disabled(!reader.canNavigate)
        Divider()
        Button(tr("Zoom In")) { reader.zoom(1.15) }.keyboardShortcut("+").disabled(!reader.canNavigate)
        Button(tr("Zoom Out")) { reader.zoom(1 / 1.15) }.keyboardShortcut("-").disabled(!reader.canNavigate)
        Button(tr("Fit to Width")) { reader.fit() }.keyboardShortcut("0").disabled(!reader.canNavigate)
        Divider()
        Button(tr("Toggle Focus Mode")) { withAnimation(AcaMotion.panels(reduced: reader.reduceMotion)) { reader.toggleFocus() } }.keyboardShortcut("f", modifiers: [.command, .shift])
        Button(tr("Close Reader"), action: close).keyboardShortcut("w", modifiers: [.command, .shift])
    }
}
