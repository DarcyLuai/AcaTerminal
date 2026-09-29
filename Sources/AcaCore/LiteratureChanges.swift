import Foundation

public struct LiteratureSnapshot: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var projectID: UUID
    public var provider: String
    public var checkedAt: Date
    public var scope: String
    public var knownWorkIDs: [String]
    public var topicState: [String: [String]]
    public var citationState: [String: [String]]
    public var authorState: [String: [String]]
    public init(cache: DiscoveryCache, previous: LiteratureSnapshot?) {
        projectID = cache.projectID; provider = cache.provider; checkedAt = cache.checkedAt; scope = cache.scope
        knownWorkIDs = Array(Set((previous?.knownWorkIDs ?? []) + cache.recommendations.map(\.id))).sorted()
        topicState = Dictionary(uniqueKeysWithValues: cache.trackedTopics.map { id in (id, cache.recommendations.filter { $0.work.topicIDs.contains(id) }.map(\.id)) })
        authorState = Dictionary(uniqueKeysWithValues: cache.trackedAuthors.map { id in (id, cache.recommendations.filter { $0.work.authorIDs.contains(id) }.map(\.id)) })
        citationState = previous?.scope == cache.scope ? previous!.citationState : [:]
        let seeds = Set(cache.seedWorkIDs)
        for rec in cache.recommendations {
            let citations = Set(rec.work.references).intersection(seeds)
            if !citations.isEmpty { citationState[rec.id] = Array(Set(citationState[rec.id] ?? []).union(citations)).sorted() }
        }
    }
}
public enum LiteratureChangeKind: String, Codable, CaseIterable {
    case newRelatedWork, newCitationToProjectPaper, newWorkByTrackedAuthor, newWorkInTrackedTopic, potentialClaimChallenge, potentialClaimSupport, potentialClaimExtension, potentialHypothesisEvidence, newWorkRelatedToResearchQuestion
}
public struct LiteratureChange: Codable, Equatable, Identifiable {
    public var id: String { work.id }
    public var work: DiscoveryWork
    public var kinds: [LiteratureChangeKind]
    public var reasons: [DiscoveryReason]
    public var important: Bool
}
public struct LiteratureChangeSet: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var projectID: UUID
    public var provider: String
    public var detectedAt: Date
    public var changes: [LiteratureChange]
    public var reviewedAt: Date?
    public var notificationClaimedAt: Date?
    public init(cache: DiscoveryCache, previous: LiteratureSnapshot?, feedback: [DiscoveryFeedback] = []) {
        projectID = cache.projectID; provider = cache.provider; detectedAt = cache.checkedAt
        // A new search scope is a baseline, not a burst of alleged new publications.
        guard let previous = previous, previous.scope == cache.scope else { changes = []; return }
        let known = Set(previous.knownWorkIDs)
        let dismissed = Set(feedback.filter { $0.projectID == cache.projectID && $0.provider == cache.provider && $0.judgment != .relevant }.map(\.workID))
        changes = cache.recommendations.compactMap { rec in
            guard !dismissed.contains(rec.id) else { return nil }
            let isNew = !known.contains(rec.id)
            let citations = Set(rec.work.references).intersection(Set(cache.seedWorkIDs))
            let newCitation = !citations.subtracting(previous.citationState[rec.id] ?? []).isEmpty
            guard isNew || newCitation else { return nil }
            var kinds: [LiteratureChangeKind] = isNew ? [.newRelatedWork] : []
            if newCitation { kinds.append(.newCitationToProjectPaper) }
            if isNew {
                if rec.reasons.contains(where: { $0.kind == .author }) { kinds.append(.newWorkByTrackedAuthor) }
                if rec.reasons.contains(where: { $0.kind == .topic }) { kinds.append(.newWorkInTrackedTopic) }
                if rec.categories.contains(.potentialChallenges) { kinds.append(.potentialClaimChallenge) }
                if rec.potentialSupport { kinds.append(.potentialClaimSupport) }
                if rec.markMatches?.contains(where: { $0.suggestion == "Potential extension" }) == true { kinds.append(.potentialClaimExtension) }
                if rec.markMatches?.contains(where: { $0.type == .hypothesis }) == true { kinds.append(.potentialHypothesisEvidence) }
                if rec.markMatches?.contains(where: { $0.type == .researchQuestion }) == true { kinds.append(.newWorkRelatedToResearchQuestion) }
            }
            return LiteratureChange(work: rec.work, kinds: kinds, reasons: rec.reasons, important: rec.isImportant || newCitation)
        }
    }
}
public extension ResearchDatabase {
    mutating func recordDiscovery(_ cache: DiscoveryCache) {
        let previous = (literatureSnapshots ?? []).filter { $0.projectID == cache.projectID && $0.provider == cache.provider }.max { $0.checkedAt < $1.checkedAt }
        if let previous = previous, cache.checkedAt < previous.checkedAt { return }
        let changes = LiteratureChangeSet(cache: cache, previous: previous, feedback: discoveryFeedback ?? [])
        var caches = discoveryCaches ?? []; caches.removeAll { $0.id == cache.id }; caches.append(cache); discoveryCaches = caches
        literatureSnapshots = (literatureSnapshots ?? []) + [LiteratureSnapshot(cache: cache, previous: previous)]
        if !changes.changes.isEmpty { literatureChanges = (literatureChanges ?? []) + [changes] }
    }
    mutating func recordFeedback(_ item: DiscoveryFeedback) {
        var all = discoveryFeedback ?? []; all.removeAll { $0.id == item.id }; all.append(item); discoveryFeedback = all
    }
    mutating func claimLiteratureNotifications(projectID: UUID, now: Date = Date()) -> [LiteratureChangeSet] {
        let pending = (literatureChanges ?? []).filter { $0.projectID == projectID && $0.notificationClaimedAt == nil }
        let ids = Set(pending.map(\.id))
        for i in (literatureChanges ?? []).indices where ids.contains(literatureChanges![i].id) { literatureChanges?[i].notificationClaimedAt = now }
        return pending
    }
    func unreviewedChanges(projectID: UUID) -> [LiteratureChange] {
        var seen = Set<String>()
        return (literatureChanges ?? []).filter { $0.projectID == projectID && $0.reviewedAt == nil }.sorted { $0.detectedAt > $1.detectedAt }.flatMap(\.changes).filter { seen.insert($0.id).inserted }
    }
    func validateAdvanced() throws {
        func unique<T: Hashable>(_ values: [T]) -> Bool { values.count == Set(values).count }
        let relations = claimRelations ?? [], projects = Set(self.projects.map(\.id))
        let claims = Dictionary(uniqueKeysWithValues: self.claims.map { ($0.id, $0.projectID) })
        guard unique(relations.map(\.id)), unique(relations.map(\.key)), relations.allSatisfy({ $0.sourceClaimID != $0.targetClaimID && projects.contains($0.projectID) && claims[$0.sourceClaimID] == $0.projectID && claims[$0.targetClaimID] == $0.projectID }) else { throw CoreError.invalid("Invalid claim relationship.") }
        let caches = discoveryCaches ?? [], feedback = discoveryFeedback ?? [], snapshots = literatureSnapshots ?? [], changes = literatureChanges ?? []
        guard unique(caches.map(\.id)), unique(feedback.map(\.id)), unique(snapshots.map(\.id)), unique(changes.map(\.id)), caches.allSatisfy({ projects.contains($0.projectID) && unique($0.recommendations.map(\.id)) }), feedback.allSatisfy({ projects.contains($0.projectID) && !$0.workID.isEmpty }), snapshots.allSatisfy({ projects.contains($0.projectID) && unique($0.knownWorkIDs) }), changes.allSatisfy({ projects.contains($0.projectID) && unique($0.changes.map(\.id)) }) else { throw CoreError.invalid("Invalid project discovery history.") }
    }
}
/// A typed local query seam for a future command palette; no language model or network.
public enum ResearchQuery { case graph(UUID), evidence(UUID), discovery(UUID), changes(UUID, since: Date?) }
public enum ResearchQueryResult { case graph(ClaimGraph), evidence([Evidence]), discovery([DiscoveryRecommendation]), changes([LiteratureChangeSet]) }
public protocol ResearchQuerying { func query(_ query: ResearchQuery) -> ResearchQueryResult }
extension ResearchDatabase: ResearchQuerying {
    public func query(_ query: ResearchQuery) -> ResearchQueryResult {
        switch query {
        case .graph(let id): return .graph(ClaimGraph(database: self, projectID: id))
        case .evidence(let id): let ids = Set(claims.first { $0.id == id }?.evidence ?? []); return .evidence(evidence.filter { ids.contains($0.id) })
        case .discovery(let id): return .discovery((discoveryCaches ?? []).filter { $0.projectID == id }.flatMap(\.recommendations))
        case .changes(let id, let date): return .changes((literatureChanges ?? []).filter { $0.projectID == id && (date == nil || $0.detectedAt >= date!) })
        }
    }
}
