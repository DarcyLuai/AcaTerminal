import Foundation

/// This request is the privacy boundary. No project text, claims, evidence or notes.
public struct DiscoveryRequest: Equatable {
    public let seedIDs: [String]
    public init(seedIDs: [String]) {
        self.seedIDs = Array(Set(seedIDs.compactMap(Self.publicID))).sorted().prefix(5).map { $0 }
    }
    public static func publicID(_ value: String) -> String? {
        let tail = value.replacingOccurrences(of: "https://openalex.org/", with: "")
        if tail.range(of: #"^W[0-9]+$"#, options: .regularExpression) != nil { return tail }
        if let doi = ResearchObjectResolver.doi(value), doi.range(of: #"^10\.[0-9]{4,9}/[^\s]+$"#, options: .regularExpression) != nil { return "https://doi.org/" + doi }
        return nil
    }
    public var scope: String { seedIDs.joined(separator: "|") }
}
public struct ProjectResearchProfile {
    public let projectID: UUID
    public let request: DiscoveryRequest
    public let localTerms: Set<String>
    public let claimTerms: [UUID: Set<String>]
    public let claimTypes: [UUID: ResearchMarkType]
    public let knownDOIs: Set<String>
    public let knownWorkIDs: Set<String>
    public init(database: ResearchDatabase, projectID: UUID) {
        self.projectID = projectID
        let claims = database.claims.filter { $0.projectID == projectID }
        let evidence = database.evidence.filter { $0.projectID == projectID }
        let paperIDs = Set(claims.flatMap(\.sources) + evidence.map(\.paperID))
        let papers = database.objects.filter { $0.projects.contains(projectID) || paperIDs.contains($0.id) }
        // Prefer stable public IDs, never a user-edited title or an unpublished manuscript.
        let seeds = papers.filter { [.paper, .book, .dataset].contains($0.type) }.compactMap { item in
            item.sources.first(where: { $0.provider == "openalex" }).map(\.externalID) ?? item.doi
        }
        request = DiscoveryRequest(seedIDs: seeds)
        let question = database.projects.first(where: { $0.id == projectID })?.question ?? ""
        var texts: [String] = [question]
        texts.append(contentsOf: claims.map(\.text))
        for paper in papers { texts.append(paper.title); texts.append(contentsOf: paper.tags) }
        for item in evidence { texts.append(item.quote); texts.append(item.note) }
        localTerms = Self.terms(texts.joined(separator: " "))
        claimTypes = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0.researchType) })
        claimTerms = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, Self.terms($0.text)) })
        knownDOIs = Set(database.objects.compactMap { ResearchObjectResolver.doi($0.doi) })
        knownWorkIDs = Set(database.objects.flatMap(\.sources).filter { $0.provider == "openalex" }.map { $0.externalID.replacingOccurrences(of: "https://openalex.org/", with: "") })
    }
    public static func terms(_ text: String) -> Set<String> {
        let stop: Set<String> = ["that", "this", "with", "from", "have", "been", "were", "their", "which", "they", "these", "there", "into", "than", "also", "research", "paper", "study", "does", "what", "when", "will", "would"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 && !stop.contains($0) })
    }
}
public struct DiscoveryWork: Codable, Equatable, Identifiable {
    public var id: String
    public var object: ResearchObject
    public var references: [String]
    public var authorIDs: [String]
    public var topicIDs: [String]
    public var publicationDate: Date?
    public var citationCount: Int
    public var providerRelated: Bool
    public init(id: String, object: ResearchObject, references: [String] = [], authorIDs: [String] = [], topicIDs: [String] = [], publicationDate: Date? = nil, citationCount: Int = 0, providerRelated: Bool = false) {
        self.id = id; self.object = object; self.references = references; self.authorIDs = authorIDs; self.topicIDs = topicIDs; self.publicationDate = publicationDate; self.citationCount = citationCount; self.providerRelated = providerRelated
    }
}
public struct DiscoveryBatch {
    public var provider: String
    public var seeds: [DiscoveryWork]
    public var works: [DiscoveryWork]
    public var checkedAt: Date
    public init(provider: String, seeds: [DiscoveryWork], works: [DiscoveryWork], checkedAt: Date = Date()) { self.provider = provider; self.seeds = seeds; self.works = works; self.checkedAt = checkedAt }
}
public protocol DiscoveryProvider {
    var identifier: String { get }
    func discover(_ request: DiscoveryRequest) async throws -> DiscoveryBatch
}
public enum DiscoveryCategory: String, Codable, CaseIterable {
    case related, potentialChallenges, methods, recent, highlyCitedUnread
    public var title: String {
        switch self { case .related: return "Highly Related"; case .potentialChallenges: return "Potential challenges"; case .methods: return "Methods to explore"; case .recent: return "Recently Published"; case .highlyCitedUnread: return "Highly Cited but Unread" }
    }
}
public struct DiscoveryReason: Codable, Equatable {
    public enum Kind: String, Codable { case sharedReferences, citesProject, relatedByProvider, topic, author, localKeywords, recent, notInLibrary }
    public var kind: Kind
    public var count: Int
    public var claimID: UUID?
    public init(_ kind: Kind, count: Int = 0, claimID: UUID? = nil) { self.kind = kind; self.count = count; self.claimID = claimID }
}
public struct PotentialMarkMatch: Codable, Equatable {
    public var markID: UUID
    public var type: ResearchMarkType
    public var suggestion: String
    public init(markID: UUID, type: ResearchMarkType, suggestion: String) { self.markID = markID; self.type = type; self.suggestion = suggestion }
}
public struct DiscoveryRecommendation: Codable, Equatable, Identifiable {
    public var id: String { work.id }
    public var work: DiscoveryWork
    public var score: Int
    public var reasons: [DiscoveryReason]
    public var categories: [DiscoveryCategory]
    public var potentialSupport: Bool
    public var markMatches: [PotentialMarkMatch]?
    public var isImportant: Bool { score >= 35 || reasons.contains { $0.kind == .citesProject } }
}
public enum DiscoveryJudgment: String, Codable, CaseIterable { case relevant, notRelevant, alreadyKnown }
public struct DiscoveryFeedback: Codable, Equatable, Identifiable {
    public var id: String { "\(projectID)|\(provider)|\(workID)" }
    public var projectID: UUID
    public var provider: String
    public var workID: String
    public var judgment: DiscoveryJudgment
    public var updatedAt: Date
    public init(projectID: UUID, provider: String, workID: String, judgment: DiscoveryJudgment, updatedAt: Date = Date()) { self.projectID = projectID; self.provider = provider; self.workID = workID; self.judgment = judgment; self.updatedAt = updatedAt }
}
public struct DiscoveryCache: Codable, Equatable, Identifiable {
    public var id: String { "\(projectID)|\(provider)" }
    public var projectID: UUID
    public var provider: String
    public var checkedAt: Date
    public var scope: String
    public var recommendations: [DiscoveryRecommendation]
    public var seedWorkIDs: [String]
    public var trackedAuthors: [String]
    public var trackedTopics: [String]
    public init(profile: ProjectResearchProfile, batch: DiscoveryBatch, feedback: [DiscoveryFeedback] = [], readDOIs: Set<String> = [], readWorkIDs: Set<String> = []) {
        projectID = profile.projectID; provider = batch.provider; checkedAt = batch.checkedAt; scope = profile.request.scope
        seedWorkIDs = batch.seeds.map(\.id)
        trackedAuthors = Array(Set(batch.seeds.flatMap { $0.authorIDs.prefix(2) })).sorted()
        trackedTopics = Array(Set(batch.seeds.flatMap { $0.topicIDs.prefix(1) })).sorted()
        let seeds = Set(batch.seeds.map(\.id)), references = Set(batch.seeds.flatMap(\.references))
        let authors = Set(trackedAuthors), topics = Set(trackedTopics)
        let judgments = Dictionary(feedback.filter { $0.projectID == profile.projectID && $0.provider == batch.provider }.map { ($0.workID, $0.judgment) }, uniquingKeysWith: { _, b in b })
        var results: [DiscoveryRecommendation] = []
        var seen = Set<String>()
        for work in batch.works where !seeds.contains(work.id) && seen.insert(work.id).inserted {
            var reasons: [DiscoveryReason] = [], score = 0, categories: [DiscoveryCategory] = [.related]
            let refs = Set(work.references), terms = ProjectResearchProfile.terms(work.object.title + " " + work.object.abstract)
            let shared = refs.intersection(references).count, cites = refs.intersection(seeds).count
            if shared > 0 { reasons.append(.init(.sharedReferences, count: shared)); score += min(30, shared * 3) }
            if cites > 0 { reasons.append(.init(.citesProject, count: cites)); score += min(40, cites * 20) }
            if work.providerRelated { reasons.append(.init(.relatedByProvider)); score += 12 }
            if !topics.isDisjoint(with: work.topicIDs) { reasons.append(.init(.topic)); score += 8 }
            if !authors.isDisjoint(with: work.authorIDs) { reasons.append(.init(.author)); score += 8 }
            let overlap = terms.intersection(profile.localTerms).count
            score += min(20, overlap * 2)
            var matches: [(UUID, Int)] = []
            for (id, words) in profile.claimTerms {
                let count = terms.intersection(words).count
                if count >= 2 { matches.append((id, count)) }
            }
            matches.sort { a, b in a.1 == b.1 ? a.0.uuidString < b.0.uuidString : a.1 > b.1 }
            if !matches.isEmpty { for match in matches.prefix(20) { reasons.append(.init(.localKeywords, count: match.1, claimID: match.0)) } }
            else if overlap > 0 { reasons.append(.init(.localKeywords, count: overlap)) }
            if let date = work.publicationDate, date <= batch.checkedAt, batch.checkedAt.timeIntervalSince(date) < 90 * 86400 { categories.append(.recent); reasons.append(.init(.recent)); score += 4 }
            let known = profile.knownWorkIDs.contains(work.id) || ResearchObjectResolver.doi(work.object.doi).map { profile.knownDOIs.contains($0) } == true
            if !known { reasons.append(.init(.notInLibrary)) }
            if work.citationCount >= 50 && !(ResearchObjectResolver.doi(work.object.doi).map { readDOIs.contains($0) } ?? false) && !readWorkIDs.contains(work.id) { categories.append(.highlyCitedUnread) }
            if !terms.isDisjoint(with: ["method", "methods", "methodology", "estimator", "identification", "measurement"]) { categories.append(.methods) }
            let challenges = !matches.isEmpty && !terms.isDisjoint(with: ["contradicts", "refutes", "challenges", "inconsistent", "contrary"])
            if challenges { categories.append(.potentialChallenges) }
            let supports = !matches.isEmpty && !terms.isDisjoint(with: ["supports", "confirms", "corroborates"])
            if judgments[work.id] == .relevant { score += 12 }
            // Keep dismissed records in cache for reversible feedback, hide in the UI.
            let extends = !matches.isEmpty && !terms.isDisjoint(with: ["extends", "extension", "generalizes"])
            let hints = matches.map { PotentialMarkMatch(markID: $0.0, type: profile.claimTypes[$0.0] ?? .claim, suggestion: challenges ? "Potential challenge" : supports ? "Potential support" : extends ? "Potential extension" : "Potential relation") }
            results.append(.init(work: work, score: score, reasons: reasons, categories: categories, potentialSupport: supports, markMatches: hints))
        }
        recommendations = results.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }
}
