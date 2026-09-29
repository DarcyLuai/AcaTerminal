import SwiftUI
import AcaCore
import AcaConnectors

extension WorkspaceStore {
    func refreshDiscovery(_ projectID: UUID, manual: Bool = true) {
        guard ready, !saveFailed, !discoveryRefreshing.contains(projectID), database.projects.contains(where: { $0.id == projectID }) else { return }
        UserDefaults.standard.set(Date(), forKey: "research.attempt." + projectID.uuidString)
        discoveryRefreshing.insert(projectID); discoveryErrors[projectID] = nil
        let snapshot = database
        discoveryTasks[projectID] = Task {
            defer { discoveryRefreshing.remove(projectID); discoveryTasks[projectID] = nil }
            do {
                let profile = await Task.detached(priority: .utility) { ProjectResearchProfile(database: snapshot, projectID: projectID) }.value
                let provider = OpenAlexDiscoveryProvider(transport: httpClient, apiKey: try credentials.read("openalex.apiKey"))
                let batch = try await provider.discover(profile.request)
                try Task.checkCancellation()
                let current = database
                let cache = await Task.detached(priority: .utility) {
                    let currentProfile = ProjectResearchProfile(database: current, projectID: projectID)
                    let read = Set(current.objects.filter { $0.lastReadAt != nil }.compactMap { ResearchObjectResolver.doi($0.doi) })
                    let readIDs = Set(current.objects.filter { $0.lastReadAt != nil }.flatMap(\.sources).filter { $0.provider == "openalex" }.map { $0.externalID.replacingOccurrences(of: "https://openalex.org/", with: "") })
                    return DiscoveryCache(profile: currentProfile, batch: batch, feedback: current.discoveryFeedback ?? [], readDOIs: read, readWorkIDs: readIDs)
                }.value
                try Task.checkCancellation()
                // Do not attach a response to a scope that changed while the network was busy.
                guard cache.scope == profile.request.scope, change({ $0.recordDiscovery(cache) }), await savedBarrier() else { return }
                await notifyLiteratureChanges(projectID)
            } catch {
                if !Task.isCancelled { discoveryErrors[projectID] = error.localizedDescription }
            }
        }
    }
    func refreshProjectsOnLaunch() {
        projectLaunchTask?.cancel()
        guard UserDefaults.standard.object(forKey: "research.autoRefresh") as? Bool != false else { return }
        // Only opted-in projects (an existing first manual discovery) are monitored.
        let stale = (database.discoveryCaches ?? []).filter {
            let lastAttempt = UserDefaults.standard.object(forKey: "research.attempt." + $0.projectID.uuidString) as? Date ?? .distantPast
            return Date().timeIntervalSince(max($0.checkedAt, lastAttempt)) >= 86400
        }.map(\.projectID)
        projectLaunchTask = Task {
            for id in stale {
                if Task.isCancelled { return }
                refreshDiscovery(id, manual: false)
                await discoveryTasks[id]?.value
                if discoveryErrors[id] != nil { return } // Stop after an outage or rate limit.
            }
        }
    }
    func feedback(_ workID: String, projectID: UUID, judgment: DiscoveryJudgment) {
        change { $0.recordFeedback(.init(projectID: projectID, provider: "openalex", workID: workID, judgment: judgment)) }
    }
    @discardableResult func importDiscovery(_ work: DiscoveryWork, projectID: UUID? = nil) -> ResearchObject? {
        var object = work.object
        if let id = projectID { object.projects = [id] }
        guard change({ try $0.apply(LibraryImport(objects: [object])) }) else { return nil }
        if case .match(let id) = ResearchObjectResolver().resolve(object, in: database.objects) { return database.objects.first { $0.id == id } }
        return database.objects.first { $0.id == object.id }
    }
    func showResearchChanges(_ projectID: UUID) {
        guard ready else { pendingProjectID = projectID; return }
        guard database.projects.contains(where: { $0.id == projectID }) else { return }
        presentMainWindow?(); reader?.close(); reader = nil; showProject(projectID); projectTab = "What's New"
    }
    func reviewChanges(_ projectID: UUID) {
        change { db in for i in (db.literatureChanges ?? []).indices where db.literatureChanges?[i].projectID == projectID && db.literatureChanges?[i].reviewedAt == nil { db.literatureChanges?[i].reviewedAt = Date() } }
    }
    func notifyLiteratureChanges(_ projectID: UUID) async {
        let pending = (database.literatureChanges ?? []).filter { $0.projectID == projectID && $0.notificationClaimedAt == nil }
        if !pending.isEmpty { guard change({ _ = $0.claimLiteratureNotifications(projectID: projectID) }), await savedBarrier() else { return } }
        let works = Set(pending.filter { $0.reviewedAt == nil }.flatMap(\.changes).filter(\.important).map(\.id))
        let title = database.projects.first { $0.id == projectID }?.title ?? ""
        if !works.isEmpty, UserDefaults.standard.object(forKey: "notifications.literature") as? Bool != false {
            await notifications.send(id: "literature|" + projectID.uuidString + "|" + pending.last!.id.uuidString, title: title, body: trf("%d important research changes", works.count), projectID: projectID)
        }
        if UserDefaults.standard.bool(forKey: "notifications.projectWeekly") {
            let key = "research.digest." + projectID.uuidString
            let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
            let recent = Set((database.literatureChanges ?? []).filter { $0.projectID == projectID && Date().timeIntervalSince($0.detectedAt) <= 7 * 86400 }.flatMap(\.changes).map(\.id))
            if Date().timeIntervalSince(last) >= 7 * 86400, !recent.isEmpty {
                UserDefaults.standard.set(Date(), forKey: key)
                await notifications.send(id: "projectWeekly|" + projectID.uuidString, title: tr("Weekly project digest"), body: title + "\n" + trf("%d newly detected works", recent.count), projectID: projectID)
            }
        }
    }
}
