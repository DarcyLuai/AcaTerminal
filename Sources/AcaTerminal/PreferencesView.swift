import SwiftUI

struct PreferencesView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("reader.width") private var width = "comfortable"
    @AppStorage("reader.gap") private var gap = "medium"
    @AppStorage("reader.restore") private var restore = true
    @AppStorage("reader.smooth") private var smooth = true
    @AppStorage("reader.progress") private var progress = true
    @AppStorage("reader.selection") private var selection = true
    @AppStorage("reader.autoProject") private var autoProject = true
    var body: some View {
        Page(title: tr("Settings")) {
            RuleSection(title: tr("General"), collapsible: true) {
                SettingsRow(title: tr("Interface language")) {
                    ChoiceField(selection: $store.interfaceLanguage, options: [("system", "Follow System"), ("en", "English"), ("zh-Hans", "简体中文")]).accessibilityLabel(tr("Interface language"))
                }
            }
            RuleSection(title: tr("Appearance"), collapsible: true) {
                SettingsRow(title: tr("Theme")) { ThemeOptions(selection: $appearance) }
            }
            RuleSection(title: tr("Reader"), collapsible: true) {
                SettingsRow(title: tr("Reading width")) { ChoiceField(selection: $width, options: [("comfortable", "Comfortable"), ("wide", "Wide")]).accessibilityLabel(tr("Reading width")) }
                SettingsRow(title: tr("Page gap")) { ChoiceField(selection: $gap, options: [("small", "Small"), ("medium", "Medium"), ("large", "Large")]).accessibilityLabel(tr("Page gap")) }
                SettingsToggleRow(title: tr("Restore reading position"), isOn: $restore)
                SettingsToggleRow(title: tr("Smooth navigation"), isOn: $smooth)
                SettingsToggleRow(title: tr("Show reading progress"), isOn: $progress)
            }
            RuleSection(title: tr("Research"), collapsible: true) {
                SettingsToggleRow(title: tr("Selection toolbar"), isOn: $selection)
                SettingsToggleRow(title: tr("Auto-link Project"), isOn: $autoProject)
            }
            ImpactPreferences()
            RuleSection(title: tr("Storage"), collapsible: true) {
                SettingsRow(title: tr("Local database")) { RowAction(title: tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([store.databaseURL]) } }
                SettingsRow(title: tr("Research backup")) { RowAction(title: tr("Export…")) { store.exportRecovery() } }
            }
        }
    }
}
struct ApplicationInformationView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("AcaTerminal")).font(.system(size: 29, design: .serif))
            Text(tr("Application Information")).font(.headline).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    information("Your research, from idea to impact.", "An open-source research lifecycle client. Read, connect evidence and follow your work through publication.")
                    information("Local storage & privacy", "Your research stays on this Mac. Credentials use Keychain. Services receive identifiers for metadata, citation checks and requested full text. Impact may refresh on launch when enabled and stale. Private notes, claims and PDFs are never uploaded. No analytics or browser sessions are collected.")
                    information("Reader", "Highlights are saved separately; original PDFs and figure colors remain unchanged. Motion follows macOS accessibility settings. Scans need a text layer for selection and search.")
                    information("Services", "Citation totals depend on the named provider. Public ORCID lookup does not authenticate identity. ORCID sign-in currently requires a personal developer client. Zotero imports are read-only; journal tracking is manual.")
                    information("Developer release", "macOS v0.1 · Local signature, not notarized. Paper Tint, OCR, cloud sync and iOS are not included. Back up the database and PDF files before upgrading.")
                    information("Open source", "Independent implementation. GPL-3.0 license. Prior-art acknowledgements, architecture and connector documentation are included with the source.")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Text(ApplicationVersion.label).font(.caption).foregroundColor(.secondary); Spacer(); Button(tr("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(32).frame(width: 540, height: 590)
    }
    func information(_ title: String, _ detail: String) -> some View { VStack(alignment: .leading, spacing: 9) { Text(tr(title)).font(.system(size: 13, weight: .semibold)); Text(tr(detail)).font(.system(size: 13)).foregroundColor(.secondary).lineSpacing(5).textSelection(.enabled) } }
}
