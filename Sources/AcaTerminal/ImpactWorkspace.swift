import SwiftUI
import AcaCore
import AcaConnectors

extension WorkspaceStore {
    func rebuildAnalytics() {
        let snapshot = database, provider = analyticsProvider
        analyticsTask?.cancel()
        analyticsTask = Task {
            let result = await Task.detached(priority: .utility) { ImpactAnalytics(database: snapshot, provider: provider) }.value
            guard !Task.isCancelled else { return }; analytics = result
        }
    }
    func refreshImpact(manual: Bool = true) {
        guard ready, !impactRefreshing, !saveFailed, let identity = database.identity else { return }
        if !manual && (!(database.impactRefresh ?? .init()).isStale() || UserDefaults.standard.object(forKey: "impact.autoRefresh") as? Bool == false) { return }
        impactRefreshing = true; impactStatus = tr("Refreshing impact…")
        change { db in var state = db.impactRefresh ?? .init(); state.lastAttempt = Date(); db.impactRefresh = state }
        impactTask = Task {
            defer { impactRefreshing = false; impactTask = nil; rebuildAnalytics() }
            do {
                let provider = OpenAlexProvider(apiKey: try credentials.read("openalex.apiKey"), transport: httpClient)
                let profile = try await provider.researcher(orcid: identity.orcid)
                guard !Task.isCancelled, database.identity?.orcid == identity.orcid else { return }
                guard change({ $0.adoptIdentity(profile) }) else { return }
                rebuildAnalytics()
                let works = database.identity?.works ?? []
                var failures = 0
                for (index, work) in works.enumerated() {
                    try Task.checkCancellation()
                    impactStatus = trf("Checking citations · %d / %d", index + 1, works.count)
                    do {
                        let observation = try await provider.citationState(for: work)
                        guard !Task.isCancelled, database.identity?.orcid == identity.orcid else { return }
                        if !change({ _ = try $0.applyCitationObservation(observation) }) { return }
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        failures += 1
                        // Stop on service failure instead of issuing a burst of failing requests.
                        impactStatus = trf("Refresh paused after %d works. Saved analytics remain available.", index)
                        if manual { self.error = error.localizedDescription }; break
                    }
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
                if failures == 0 {
                    change { db in var state = db.impactRefresh ?? .init(); state.lastCompleted = Date(); db.impactRefresh = state }
                    impactStatus = tr("Impact is up to date")
                }
                await notifyCitationEvents()
                await notifyWeeklySummary()
            } catch {
                impactStatus = tr(Task.isCancelled ? "Refresh cancelled" : "Refresh unavailable · saved analytics retained")
                if manual && !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func cancelImpactRefresh() { impactTask?.cancel() }
    func showCitation(_ id: String) {
        guard database.citationEvents?.contains(where: { $0.id == id }) == true else { pendingCitationID = id; return }
        presentMainWindow?(); closeReader(); destination = .impact; selectedCitationID = id
        change { db in if let index = db.citationEvents?.firstIndex(where: { $0.id == id }) { db.citationEvents?[index].seen = true } }
    }
    func importCitingWork(_ event: CitationEvent) -> ResearchObject? {
        let work = event.citingWork
        if let existing = database.objects.first(where: { object in object.sources.contains { old in work.sources.contains { $0.provider == old.provider && $0.externalID == old.externalID } } }) { return existing }
        if case .match(let id) = ResearchObjectResolver().resolve(work, in: database.objects) { return database.objects.first { $0.id == id } }
        return change({ $0.objects.append(work) }) ? work : nil
    }
    func savedBarrier() async -> Bool {
        guard let repository = repository else { return false }
        await withCheckedContinuation { continuation in repository.drain { continuation.resume() } }
        return !saveFailed
    }
    func notifyCitationEvents() async {
        let events = (database.citationEvents ?? []).filter { $0.notificationClaimedAt == nil }
        guard !events.isEmpty else { return }
        // Persist a claim before talking to the OS: at-most-once, including after relaunch.
        guard change({ _ = $0.claimCitationNotifications() }), await savedBarrier() else { return }
        guard UserDefaults.standard.object(forKey: "notifications.citations") as? Bool != false else { return }
        for event in events where !event.seen {
            let citedTitle = database.objects.first { $0.id == event.citedWorkID }?.title ?? ""
            let authors = event.citingWork.authors.prefix(2).map(\.name).joined(separator: " & ")
            await notifications.send(id: "citation|" + event.id, title: tr("New citation"), body: event.citingWork.title + "\n" + trf("cited %@", citedTitle) + "\n" + authors, citationID: event.id)
        }
    }
    func notifyWeeklySummary() async {
        guard UserDefaults.standard.bool(forKey: "notifications.weekly"), Date().timeIntervalSince(database.impactRefresh?.lastWeeklySummary ?? .distantPast) >= 7 * 86400 else { return }
        let now = Date(), count = (database.citationEvents ?? []).filter { now.timeIntervalSince($0.detectedAt) <= 7 * 86400 }.count
        guard count > 0 else { return }
        guard change({ db in var state = db.impactRefresh ?? .init(); state.lastWeeklySummary = now; db.impactRefresh = state }), await savedBarrier() else { return }
        await notifications.send(id: "weekly|" + String(Int(now.timeIntervalSince1970 / (7 * 86400))), title: tr("Weekly impact summary"), body: trf("%d newly detected citations · OpenAlex", count))
    }
}
