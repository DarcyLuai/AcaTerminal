import Foundation
public protocol Connector { var identifier: String { get }; var displayName: String { get } }
public struct LibraryImport {
    public var objects: [ResearchObject]
    public var notes: [ResearchNote]
    public var collections: [LibraryCollection]
    public init(objects: [ResearchObject], notes: [ResearchNote] = [], collections: [LibraryCollection] = []) { self.objects = objects; self.notes = notes; self.collections = collections }
}
public protocol LibraryProvider: Connector { func importLibrary() async throws -> LibraryImport }
public protocol SubmissionConnector: Connector {
    func fetchSubmissions() async throws -> [Submission]
    func refresh(_ submission: Submission) async throws -> Submission
}
public protocol CitationProvider: Connector {
    func metrics(for object: ResearchObject) async throws -> (ResearchObject, CitationMetrics)
    func researcher(orcid: String) async throws -> ResearcherIdentity
}
public protocol CredentialStore {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func remove(_ key: String) throws
}
public protocol ResearchRepository {
    func load() throws -> ResearchDatabase
    func save(_ database: ResearchDatabase) throws
}
public protocol AcaTexBridge { func export(_ exchange: AcaResearchExchange) throws -> Data }
public struct AcaResearchExchange: Codable {
    public let schemaVersion: Int
    public let type: String
    public let doi: String?
    public let citeKey: String
    public let title: String
    public let authors: [Author]
    public let year: Int?
    public let projectIDs: [UUID]
    public let sources: [SourceReference]
    public init(object: ResearchObject, citeKey: String) {
        schemaVersion = 1; type = "citation"; doi = object.doi; self.citeKey = citeKey; title = object.title
        authors = object.authors; year = object.year; projectIDs = object.projects; sources = object.sources.filter { $0.url?.isFileURL != true && !["local-pdf", "local-document"].contains($0.provider) }
    }
}
public struct JSONResearchBridge: AcaTexBridge {
    public init() {}
    public func export(_ exchange: AcaResearchExchange) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exchange)
    }
}
