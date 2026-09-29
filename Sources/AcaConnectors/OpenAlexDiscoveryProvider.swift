import Foundation
import AcaCore

/// Bounded public-ID exploration. Project text is deliberately not accepted here.
public struct OpenAlexDiscoveryProvider: DiscoveryProvider {
    public let identifier = "openalex"
    private let transport: HTTPTransport
    private let apiKey: String?
    public init(transport: HTTPTransport = HTTPClient(), apiKey: String? = nil) { self.transport = transport; self.apiKey = apiKey }
    public func discover(_ request: DiscoveryRequest) async throws -> DiscoveryBatch {
        guard !request.seedIDs.isEmpty else { throw CoreError.invalid("Add a published paper with a DOI or OpenAlex ID to this project first.") }
        var seeds: [PublicWork] = []
        for id in request.seedIDs { try Task.checkCancellation(); seeds.append(try await get(path: "works/" + id)) }
        let seedIDs = seeds.map { Self.short($0.id) }
        let related = Array(Set(seeds.flatMap { $0.related_works ?? [] }.map(Self.short))).sorted().prefix(50)
        var candidates: [PublicWork] = []
        if !related.isEmpty { candidates += try await list("openalex:" + related.joined(separator: "|"), sort: nil) }
        candidates += try await list("cites:" + seedIDs.joined(separator: "|"), sort: "publication_date:desc")
        let topics = Array(Set(seeds.compactMap { $0.primary_topic?.id }.map(Self.short))).sorted().prefix(5)
        if !topics.isEmpty { candidates += try await list("primary_topic.id:" + topics.joined(separator: "|"), sort: "publication_date:desc") }
        let authors = Array(Set(seeds.flatMap { $0.authorships.prefix(2).compactMap { $0.author.id }.map(Self.short) })).sorted().prefix(10)
        if !authors.isEmpty { candidates += try await list("authorships.author.id:" + authors.joined(separator: "|"), sort: "publication_date:desc") }
        try Task.checkCancellation()
        let relatedIDs = Set(related)
        return DiscoveryBatch(provider: identifier, seeds: seeds.map { $0.work }, works: candidates.map { value in var work = value.work; work.providerRelated = relatedIDs.contains(work.id); return work })
    }
    private func list(_ filter: String, sort: String?) async throws -> [PublicWork] {
        var query = [URLQueryItem(name: "filter", value: filter), URLQueryItem(name: "per-page", value: "50")]
        if let sort = sort { query.append(.init(name: "sort", value: sort)) }
        let response: Page = try await get(path: "works", query: query); return response.results
    }
    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(); components.scheme = "https"; components.host = "api.openalex.org"; components.path = "/" + path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CoreError.invalid("Invalid public work identifier.") }
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = apiKey, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        return try JSONDecoder().decode(T.self, from: await transport.data(for: request))
    }
    private static func short(_ id: String) -> String { id.split(separator: "/").last.map(String.init) ?? id }
    private struct Page: Decodable { var results: [PublicWork] }
    private struct Entity: Decodable { var id: String?; var display_name: String? }
    private struct Authorship: Decodable { var author: Entity }
    private struct Location: Decodable { var source: Entity?; var landing_page_url: URL? }
    private struct PublicWork: Decodable {
        var id: String; var display_name: String?; var doi: String?; var publication_year: Int?; var publication_date: String?
        var authorships: [Authorship]; var primary_topic: Entity?; var primary_location: Location?
        var referenced_works: [String]?; var related_works: [String]?; var cited_by_count: Int?
        var abstract_inverted_index: [String: [Int]]?
        var work: DiscoveryWork {
            var item = ResearchObject(title: display_name ?? id, authors: authorships.map { Author($0.author.display_name ?? "") }, year: publication_year, doi: doi)
            item.venue = primary_location?.source?.display_name ?? ""
            item.sources = [.init(provider: "openalex", externalID: OpenAlexDiscoveryProvider.short(id), url: URL(string: id))]
            let words = (abstract_inverted_index ?? [:]).flatMap { key, positions in positions.map { ($0, key) } }.sorted { $0.0 < $1.0 }
            item.abstract = words.map { $0.1 }.joined(separator: " ")
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
            return DiscoveryWork(id: OpenAlexDiscoveryProvider.short(id), object: item, references: (referenced_works ?? []).map(OpenAlexDiscoveryProvider.short), authorIDs: authorships.compactMap { $0.author.id }.map(OpenAlexDiscoveryProvider.short), topicIDs: primary_topic?.id.map { [OpenAlexDiscoveryProvider.short($0)] } ?? [], publicationDate: publication_date.flatMap { formatter.date(from: $0) }, citationCount: cited_by_count ?? 0)
        }
    }
}
