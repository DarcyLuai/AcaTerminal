import SwiftUI

struct ImpactPreferences: View {
    @EnvironmentObject var store: WorkspaceStore
    @AppStorage("interfaceLanguage") private var language = "system"
    @AppStorage("unpaywall.email") private var email = ""
    @AppStorage("scholar.profile") private var scholar = ""
    @AppStorage("impact.autoRefresh") private var autoRefresh = true
    @AppStorage("notifications.citations") private var citations = true
    @AppStorage("notifications.submissions") private var submissions = true
    @AppStorage("notifications.weekly") private var weekly = false
    @AppStorage("research.autoRefresh") private var researchRefresh = true
    @AppStorage("notifications.literature") private var literature = true
    @AppStorage("notifications.projectWeekly") private var projectWeekly = false
    var body: some View {
        RuleSection(title: "Full text & impact", collapsible: true) {
            SettingsRow(title: "Unpaywall contact email") { TextField(tr("Email sent only to Unpaywall"), text: $email).textFieldStyle(.roundedBorder) }
            SettingsRow(title: "Google Scholar profile") { TextField("https://scholar.google.com/citations?user=…", text: $scholar).textFieldStyle(.roundedBorder) }
            SettingsToggleRow(title: "Refresh on launch if stale", isOn: $autoRefresh)
        }
        RuleSection(title: "Research Monitoring", collapsible: true) {
            SettingsToggleRow(title: "Refresh monitored projects on launch", isOn: $researchRefresh)
            SettingsToggleRow(title: "Important literature changes", isOn: $literature)
            SettingsToggleRow(title: "Weekly project digest", isOn: $projectWeekly)
            Text(tr("Monitoring starts after a project's first discovery. Refreshes at most once per day on launch; private research text stays on this Mac.")).font(.caption).foregroundColor(.secondary).padding(.vertical, 14)
        }
        RuleSection(title: "Notifications", collapsible: true) {
            SettingsToggleRow(title: "New citations", isOn: $citations)
            SettingsToggleRow(title: "Submission changes", isOn: $submissions)
            SettingsToggleRow(title: "Weekly impact summary", isOn: $weekly)
            NotificationPermissionRow(service: store.notifications)
        }
    }
}
struct NotificationPermissionRow: View {
    @ObservedObject var service: ResearchNotifications
    @AppStorage("interfaceLanguage") private var language = "system"
    var body: some View {
        SettingsRow(title: "macOS permission") { VStack(alignment: .trailing, spacing: 8) { Text(tr(service.status)).font(.caption).foregroundColor(.secondary); Button { Task { await service.requestPermission() } } label: { HStack { if service.requestingPermission { ProgressView().controlSize(.small) }; Text(tr("Enable system notifications…")) } }.disabled(service.requestingPermission); if let error = service.lastFailure { Text(error).font(.caption).foregroundColor(.secondary) } } }.task { await service.updateStatus() }
    }
}
