import Foundation
import UserNotifications

@MainActor final class ResearchNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status = "Not requested"
    @Published var requestingPermission = false
    @Published var lastFailure: String?
    var onCitation: ((String) -> Void)?
    var onProject: ((UUID) -> Void)?
    private var center: UNUserNotificationCenter? { Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current() }
    func configure() { center?.delegate = self; Task { await updateStatus() } }
    func updateStatus() async {
        guard let center = center else { status = "Unavailable in command-line build"; return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: status = "Allowed"; case .denied: status = "Disabled in macOS Settings"; default: status = "Not requested" }
    }
    func requestPermission() async {
        guard !requestingPermission else { return }; requestingPermission = true
        defer { requestingPermission = false }
        do { _ = try await center?.requestAuthorization(options: [.alert, .sound, .badge]); await updateStatus() }
        catch { lastFailure = error.localizedDescription }
    }
    func send(id: String, title: String, body: String, citationID: String? = nil, projectID: UUID? = nil) async {
        guard let center = center else { return }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        if let id = citationID { content.userInfo = ["citationEventID": id] }
        if let id = projectID { content.userInfo["projectID"] = id.uuidString }
        do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        catch { lastFailure = error.localizedDescription }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["citationEventID"] as? String
        let projectID = (response.notification.request.content.userInfo["projectID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in if let id = id { onCitation?(id) }; if let id = projectID { onProject?(id) }; completionHandler() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
}
