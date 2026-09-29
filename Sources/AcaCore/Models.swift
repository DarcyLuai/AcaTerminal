import Foundation

public enum ObjectKind: String, Codable, CaseIterable { case paper, book, dataset, code, manuscript, note, person, project }
public struct Author: Codable, Hashable {
    public var name: String
    public var orcid: String?
    public init(_ name: String, orcid: String? = nil) { self.name = name; self.orcid = orcid }
}
public struct SourceReference: Codable, Hashable, Identifiable {
    public var id: String { provider + ":" + externalID }
    public var provider: String
    public var externalID: String
    public var url: URL?
    public var lastSynced: Date
    public var metadata: [String: String]
    public init(provider: String, externalID: String, url: URL? = nil, lastSynced: Date = Date(), metadata: [String: String] = [:]) {
        self.provider = provider; self.externalID = externalID; self.url = url; self.lastSynced = lastSynced; self.metadata = metadata
    }
}
public struct ResearchObject: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var type: ObjectKind = .paper
    public var title: String
    public var authors: [Author] = []
    public var doi: String?
    public var arxivID: String?
    public var isbn: String?
    public var year: Int?
    public var venue: String = ""
    public var abstract: String = ""
    public var sources: [SourceReference] = []
    public var projects: [UUID] = []
    public var tags: [String] = []
    public var createdAt = Date()
    public var updatedAt = Date()
    public var lastReadAt: Date?
    public init(title: String, authors: [Author] = [], year: Int? = nil, doi: String? = nil) {
        self.title = title; self.authors = authors; self.year = year; self.doi = doi
    }
}
public struct ResearchProject: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var title: String
    public var question: String
    public var createdAt = Date()
    public var updatedAt = Date()
    public init(title: String, question: String = "") { self.title = title; self.question = question }
}
public struct Claim: Codable, Hashable, Identifiable {
    public var markType: ResearchMarkType?
    public var markStatus: String?
    public var id = UUID()
    public var projectID: UUID
    public var text: String
    public var sources: [UUID] = []
    public var evidence: [UUID] = []
    public var createdAt = Date()
    public var updatedAt = Date()
    public init(projectID: UUID, text: String) { self.projectID = projectID; self.text = text }
}
public enum EvidenceRelationship: String, Codable, CaseIterable { case supports, challenges, qualifies, extends, background, contradicts
    public static let selectable: [Self] = [.supports, .challenges, .qualifies, .extends, .background]
}
public struct Evidence: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var paperID: UUID
    public var page: String
    public var quote: String
    public var note: String
    public var projectID: UUID?
    public var documentID: String?
    public var locations: [PDFTextLocation]?
    public var relationship: EvidenceRelationship
    public var createdAt = Date()
    public init(paperID: UUID, page: String = "", quote: String = "", note: String = "", relationship: EvidenceRelationship = .supports) {
        self.paperID = paperID; self.page = page; self.quote = quote; self.note = note; self.relationship = relationship
    }
}
public struct ResearchNote: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var paperID: UUID
    public var text: String
    public var page: String?
    public var sourceStatement: String?
    public var sourceID: String?
    public var createdAt = Date()
    public init(paperID: UUID, text: String, sourceID: String? = nil) { self.paperID = paperID; self.text = text; self.sourceID = sourceID }
}
public struct LibraryCollection: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var parentID: String?
    public init(id: String, name: String, parentID: String? = nil) { self.id = id; self.name = name; self.parentID = parentID }
}
public struct CitationYear: Codable, Hashable, Identifiable {
    public var id: Int { year }
    public var year: Int
    public var count: Int
    public init(year: Int, count: Int) { self.year = year; self.count = count }
}
public struct CitationMetrics: Codable, Hashable {
    public var citationCount: Int
    public var hIndex: Int?
    public var worksCount: Int?
    public var citationsByYear: [CitationYear]
    public var citingWorks: [String]
    public var updatedAt: Date
    public var provider: String
    public init(citationCount: Int, hIndex: Int? = nil, worksCount: Int? = nil, citationsByYear: [CitationYear] = [], citingWorks: [String] = [], updatedAt: Date = Date(), provider: String) {
        self.citationCount = citationCount; self.hIndex = hIndex; self.worksCount = worksCount; self.citationsByYear = citationsByYear
        self.citingWorks = citingWorks; self.updatedAt = updatedAt; self.provider = provider
    }
}
public struct CitationSnapshot: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var objectID: UUID
    public var metrics: CitationMetrics
    public init(objectID: UUID, metrics: CitationMetrics) { self.objectID = objectID; self.metrics = metrics }
}
public struct ResearcherIdentity: Codable, Hashable {
    public var name: String
    public var orcid: String
    public var authenticated: Bool
    public var metrics: CitationMetrics?
    public var works: [ResearchObject]
    public var workMetrics: [String: CitationMetrics]?
    public init(name: String, orcid: String, authenticated: Bool = false, metrics: CitationMetrics? = nil, works: [ResearchObject] = []) {
        self.name = name; self.orcid = orcid; self.authenticated = authenticated; self.metrics = metrics; self.works = works
    }
}
public struct ResearchDatabase: Codable, Equatable {
    public var formatVersion = 5
    public var acaTexConnections: [AcaTexConnection]?
    public var markBindings: [MarkBinding]?
    public var evidenceRelations: [EvidenceRelation]?
    public var claimRelations: [ClaimRelation]?
    public var discoveryCaches: [DiscoveryCache]?
    public var discoveryFeedback: [DiscoveryFeedback]?
    public var literatureSnapshots: [LiteratureSnapshot]?
    public var literatureChanges: [LiteratureChangeSet]?
    public var citationEvents: [CitationEvent]?
    public var citationStates: [CitationState]?
    public var impactRefresh: ImpactRefreshState?
    public var readingStates: [ReadingPosition]?
    public var highlights: [ReaderHighlight]?
    public var objects: [ResearchObject] = []
    public var projects: [ResearchProject] = []
    public var claims: [Claim] = []
    public var evidence: [Evidence] = []
    public var notes: [ResearchNote] = []
    public var submissions: [Submission] = []
    public var collections: [LibraryCollection] = []
    public var citationSnapshots: [CitationSnapshot] = []
    public var identity: ResearcherIdentity?
    public init() {}
    public func latestMetrics(for id: UUID) -> CitationMetrics? {
        citationSnapshots.filter { $0.objectID == id }.max { $0.metrics.updatedAt < $1.metrics.updatedAt }?.metrics
    }
    public mutating func addEvidence(_ item: Evidence, to claimID: UUID) throws {
        guard let claim = claims.first(where: { $0.id == claimID }) else { throw CoreError.invalid("Choose an existing claim.") }
        try saveEvidence(item, projectID: claim.projectID, claimID: claimID)
    }
}
public enum CoreError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
