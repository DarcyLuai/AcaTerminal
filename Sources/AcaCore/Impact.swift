import Foundation

public enum CitationProviderID {
    public static func canonical(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace && $0 != "-" } }
}
public extension CitationSnapshot {
    var paperID: UUID { objectID }
    var provider: String { CitationProviderID.canonical(metrics.provider) }
    var citationCount: Int { metrics.citationCount }
    var timestamp: Date { metrics.updatedAt }
}
public struct CitingWork: Codable, Equatable, Identifiable {
    public var id: String
    public var object: ResearchObject
    public var publicationDate: Date?
    public var context: String?
    public var intent: String?
    public var isInfluential: Bool?
    public init(id: String, object: ResearchObject, publicationDate: Date? = nil) { self.id = id; self.object = object; self.publicationDate = publicationDate }
}
public struct CitationState: Codable, Equatable, Identifiable {
    public var id: String { citedWorkID.uuidString + "|" + provider }
    public var citedWorkID: UUID
    public var provider: String
    public var knownCitingWorks: [String]
    public var baselineAt: Date
    public var lastCheckedAt: Date
    public init(citedWorkID: UUID, provider: String, knownCitingWorks: [String], at: Date) { self.citedWorkID = citedWorkID; self.provider = CitationProviderID.canonical(provider); self.knownCitingWorks = knownCitingWorks; baselineAt = at; lastCheckedAt = at }
}
public struct CitationEvent: Codable, Equatable, Identifiable {
    public var id: String { citedWorkID.uuidString + "|" + provider + "|" + citingWorkID }
    public var citedWorkID: UUID
    public var citingWorkID: String
    public var provider: String
    public var detectedAt: Date
    public var publicationDate: Date?
    public var seen: Bool
    public var citingWork: ResearchObject
    public var notificationClaimedAt: Date?
    public var context: String?
    public var intent: String?
    public var isInfluential: Bool?
    public init(citedWorkID: UUID, work: CitingWork, provider: String, detectedAt: Date) {
        self.citedWorkID = citedWorkID; citingWorkID = work.id; self.provider = CitationProviderID.canonical(provider); self.detectedAt = detectedAt; publicationDate = work.publicationDate; seen = false; citingWork = work.object; context = work.context; intent = work.intent; isInfluential = work.isInfluential
    }
}
public struct CitationObservation {
    public var object: ResearchObject
    public var metrics: CitationMetrics
    public var citingWorks: [CitingWork]
    public var complete: Bool
    public init(object: ResearchObject, metrics: CitationMetrics, citingWorks: [CitingWork], complete: Bool) { self.object = object; self.metrics = metrics; self.citingWorks = citingWorks; self.complete = complete }
}
public protocol CitationMonitor: Connector { func citationState(for object: ResearchObject) async throws -> CitationObservation }
public struct ImpactRefreshState: Codable, Equatable {
    public var lastAttempt: Date?
    public var lastCompleted: Date?
    public var lastWeeklySummary: Date?
    public init() {}
    public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(lastAttempt ?? .distantPast) >= 24 * 3600 }
}
public struct ImpactPaper: Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var citationCount: Int
    public var growthPerDay: Double?
    public var recentDetection: Date?
}
public struct ImpactYear: Identifiable, Equatable {
    public var id: Int { year }; public var year: Int; public var count: Int; public var cumulative: Int
}
public struct ImpactPoint: Identifiable, Equatable {
    public var id: UUID; public var paperID: UUID; public var title: String; public var date: Date; public var count: Int
}
public struct ImpactAnalytics: Equatable {
    public var provider: String
    public var citationCount: Int?
    public var hIndex: Int?
    public var worksCount: Int
    public var thisYear: Int?
    public var years: [ImpactYear]
    public var papers: [ImpactPaper]
    public var worksByYear: [ImpactYear]
    public var observations: [ImpactPoint]
    public var updatedAt: Date?
    public var newEventsThisWeek: Int
    public init(database: ResearchDatabase, provider: String, now: Date = Date()) {
        let providerID = CitationProviderID.canonical(provider)
        self.provider = providerID
        let works = database.identity?.works ?? []
        let ids = Set(works.map(\.id))
        let snapshots = database.citationSnapshots.filter { $0.provider == providerID && ids.contains($0.objectID) }
        let grouped = Dictionary(grouping: snapshots, by: \.objectID)
        let events = (database.citationEvents ?? []).filter { $0.provider == providerID && ids.contains($0.citedWorkID) }
        let recent = Dictionary(grouping: events, by: \.citedWorkID).mapValues { $0.map(\.detectedAt).max()! }
        papers = works.compactMap { work in
            let history = (grouped[work.id] ?? []).sorted { $0.timestamp < $1.timestamp }
            guard let last = history.last else { return nil }
            let first = history.first!
            let days = last.timestamp.timeIntervalSince(first.timestamp) / 86400
            return ImpactPaper(id: work.id, title: work.title, citationCount: last.citationCount, growthPerDay: days >= 1 ? Double(last.citationCount - first.citationCount) / days : nil, recentDetection: recent[work.id])
        }
        let metrics = database.identity?.metrics.flatMap { CitationProviderID.canonical($0.provider) == providerID ? $0 : nil }
        citationCount = metrics?.citationCount
        hIndex = metrics?.hIndex
        worksCount = metrics?.worksCount ?? works.count
        updatedAt = max(metrics?.updatedAt ?? .distantPast, snapshots.map(\.timestamp).max() ?? .distantPast)
        if updatedAt == .distantPast { updatedAt = nil }
        var cumulative = 0
        years = (metrics?.citationsByYear ?? []).sorted { $0.year < $1.year }.map { cumulative += $0.count; return .init(year: $0.year, count: $0.count, cumulative: cumulative) }
        thisYear = years.first { $0.year == Calendar.current.component(.year, from: now) }?.count
        worksByYear = Dictionary(grouping: works.compactMap(\.year), by: { $0 }).map { .init(year: $0.key, count: $0.value.count, cumulative: 0) }.sorted { $0.year < $1.year }
        let titles = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0.title) })
        observations = snapshots.map { .init(id: $0.id, paperID: $0.paperID, title: titles[$0.paperID] ?? "", date: $0.timestamp, count: $0.citationCount) }.sorted { $0.date < $1.date }
        newEventsThisWeek = events.filter { now.timeIntervalSince($0.detectedAt) >= 0 && now.timeIntervalSince($0.detectedAt) <= 7 * 86400 }.count
    }
    public func sortedPapers(by sort: String) -> [ImpactPaper] {
        papers.sorted { a,b in
            if sort == "recent", a.recentDetection != b.recentDetection { return (a.recentDetection ?? .distantPast) > (b.recentDetection ?? .distantPast) }
            if sort == "growth", a.growthPerDay != b.growthPerDay { return (a.growthPerDay ?? -.infinity) > (b.growthPerDay ?? -.infinity) }
            return a.citationCount == b.citationCount ? a.title < b.title : a.citationCount > b.citationCount
        }
    }
}
public extension ResearchDatabase {
    /// First complete observation is a silent baseline. IDs are retained even if a provider later removes a citation.
    @discardableResult mutating func applyCitationObservation(_ observation: CitationObservation) throws -> [CitationEvent] {
        guard observation.complete, let index = objects.firstIndex(where: { $0.id == observation.object.id }) else { throw CoreError.invalid("Citation observation is incomplete or the work is missing.") }
        let provider = CitationProviderID.canonical(observation.metrics.provider)
        let now = observation.metrics.updatedAt
        let key = observation.object.id.uuidString + "|" + provider
        let prior = (citationStates ?? []).first { $0.id == key }
        if let prior = prior, now < prior.lastCheckedAt { throw CoreError.invalid("An older citation observation cannot replace a newer one.") }
        let known = Set(prior?.knownCitingWorks ?? [])
        let incoming = Set(observation.citingWorks.map(\.id))
        var existing = Set((citationEvents ?? []).map(\.id))
        let events: [CitationEvent] = prior == nil ? [] : observation.citingWorks.filter { !known.contains($0.id) }.map { CitationEvent(citedWorkID: observation.object.id, work: $0, provider: provider, detectedAt: now) }.filter { existing.insert($0.id).inserted }
        objects[index] = ResearchObjectResolver().merge(observation.object, into: objects[index])
        citationSnapshots.append(.init(objectID: observation.object.id, metrics: observation.metrics))
        var state = prior ?? CitationState(citedWorkID: observation.object.id, provider: provider, knownCitingWorks: [], at: now)
        state.knownCitingWorks = known.union(incoming).sorted(); state.lastCheckedAt = now
        var states = citationStates ?? []; states.removeAll { $0.id == key }; states.append(state); citationStates = states
        citationEvents = (citationEvents ?? []) + events
        return events
    }
    mutating func adoptIdentity(_ incoming: ResearcherIdentity) {
        var profile = incoming
        let resolver = ResearchObjectResolver()
        profile.works = incoming.works.map { work in
            let exact = objects.first { existing in
                existing.sources.contains { old in work.sources.contains { $0.provider == old.provider && $0.externalID == old.externalID } }
            }?.id
            let target: UUID?
            if let exact = exact { target = exact } else if case .match(let id) = resolver.resolve(work, in: objects) { target = id } else { target = nil }
            if let target = target, let index = objects.firstIndex(where: { $0.id == target }) { objects[index] = resolver.merge(work, into: objects[index]); return objects[index] }
            objects.append(work); return work
        }
        if let current = identity, current.orcid == profile.orcid { profile.authenticated = current.authenticated }
        var uniqueWorkIDs = Set<UUID>()
        profile.works = profile.works.filter { uniqueWorkIDs.insert($0.id).inserted }
        for work in profile.works {
            if let externalID = work.sources.first(where: { $0.provider == "openalex" })?.externalID, let metrics = incoming.workMetrics?[externalID] { citationSnapshots.append(.init(objectID: work.id, metrics: metrics)) }
        }
        identity = profile
    }
}
public extension ResearchDatabase {
    /// A durable notification claim is intentionally at-most-once, not guaranteed delivery.
    mutating func claimCitationNotifications(at date: Date = Date()) -> [CitationEvent] {
        let events = (citationEvents ?? []).filter { $0.notificationClaimedAt == nil }
        for index in (citationEvents ?? []).indices where citationEvents?[index].notificationClaimedAt == nil { citationEvents?[index].notificationClaimedAt = date }
        return events
    }
}
