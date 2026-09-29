import Foundation
import AcaCore
public struct OpenAlexProvider: CitationProvider, FullTextProvider, CitationMonitor {
    public let identifier = "openalex"
    public let displayName = "OpenAlex"
    private let key: String?
    private let transport: HTTPTransport
    public init(apiKey: String? = nil, transport: HTTPTransport = HTTPClient()) { key = apiKey; self.transport = transport }
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(); components.scheme = "https"; components.host = "api.openalex.org"; components.path = "/" + path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CoreError.invalid("Invalid OpenAlex identifier.") }
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = key, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        return try JSONDecoder().decode(T.self, from: await transport.data(for: request))
    }
    public func metrics(for object: ResearchObject) async throws -> (ResearchObject, CitationMetrics) {
        let work: Work = try await get(workPath(object))
        var updated = object
        let source = SourceReference(provider: identifier, externalID: work.id, url: URL(string: work.id))
        updated.sources.removeAll { $0.provider == identifier }; updated.sources.append(source)
        if updated.abstract.isEmpty { updated.abstract = work.abstractText }
        return (updated, work.metrics)
    }
    private func workPath(_ object: ResearchObject) throws -> String {
        if let source = object.sources.first(where: { $0.provider.lowercased() == "openalex" }), let id = source.externalID.split(separator: "/").last, id.range(of: #"^W[0-9]+$"#, options: .regularExpression) != nil { return "works/" + id }
        guard let doi = ResearchObjectResolver.doi(object.doi), doi.hasPrefix("10."), doi.contains("/") else { throw CoreError.invalid("Add a DOI or OpenAlex Work ID to retrieve this work.") }
        return "works/https://doi.org/" + doi
    }
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        if object.doi == nil && !object.sources.contains(where: { $0.provider == identifier }) { return [] }
        let work: Work = try await get(workPath(object))
        return (work.locations ?? []).compactMap { location in
            guard let address = location.is_oa == true ? (location.pdf_url ?? location.landing_page_url) : location.landing_page_url, let url = URL(string: address), url.scheme == "https" else { return nil }
            let isJSTOR = url.host == "jstor.org" || url.host?.hasSuffix(".jstor.org") == true
            return .init(provider: isJSTOR ? "JSTOR · OpenAlex" : displayName, url: url, accessType: location.is_oa == true ? .openAccess : isJSTOR ? .institutional : .landingPage, version: .init(apiValue: location.version), isDirectPDF: location.is_oa == true && location.pdf_url != nil, hostType: location.source?.type)
        }
    }
    public func researcher(orcid: String) async throws -> ResearcherIdentity {
        let id = try ORCIDIdentity.normalize(orcid)
        let author: Researcher = try await get("authors/https://orcid.org/" + id)
        guard let authorID = author.id.split(separator: "/").last, authorID.hasPrefix("A") else { throw CoreError.invalid("OpenAlex returned an invalid author identifier.") }
        let works = try await allWorks(filter: "author.id:" + authorID)
        var profile = ResearcherIdentity(name: author.display_name, orcid: id, metrics: .init(citationCount: author.cited_by_count, hIndex: author.summary_stats?.h_index, worksCount: author.works_count, citationsByYear: author.counts_by_year?.map { .init(year: $0.year, count: $0.cited_by_count) } ?? [], provider: displayName), works: works.map(\.object))
        profile.workMetrics = Dictionary(uniqueKeysWithValues: works.map { ($0.id, $0.metrics) })
        return profile
    }
    public func citationState(for object: ResearchObject) async throws -> CitationObservation {
        let work: Work = try await get(workPath(object))
        guard let id = work.id.split(separator: "/").last, id.range(of: #"^W[0-9]+$"#, options: .regularExpression) != nil else { throw CoreError.invalid("OpenAlex returned an invalid work identifier.") }
        let citing = try await allWorks(filter: "cites:" + id)
        var enriched = object
        enriched.sources.removeAll { $0.provider == identifier }; enriched.sources += work.object.sources
        if enriched.abstract.isEmpty { enriched.abstract = work.abstractText }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return .init(object: enriched, metrics: work.metrics, citingWorks: citing.map { .init(id: $0.id, object: $0.object, publicationDate: $0.publication_date.flatMap(formatter.date(from:))) }, complete: true)
    }
    private func allWorks(filter: String) async throws -> [Work] {
        var cursor = "*"; var visited = Set<String>(); var seen = Set<String>(); var result: [Work] = []
        while visited.insert(cursor).inserted {
            try Task.checkCancellation()
            let page: WorkPage = try await get("works", query: [.init(name: "filter", value: filter), .init(name: "sort", value: "publication_date:desc"), .init(name: "per_page", value: "100"), .init(name: "cursor", value: cursor)])
            guard (page.meta?.count ?? 0) <= 10000 else { throw CoreError.invalid("This work list exceeds the current 10,000-record refresh limit. Existing history is unchanged.") }
            result += page.results.filter { seen.insert($0.id).inserted }
            guard result.count <= 10000 else { throw CoreError.invalid("This work list exceeds the current 10,000-record refresh limit. Existing history is unchanged.") }
            guard let next = page.meta?.next_cursor, !next.isEmpty, !page.results.isEmpty else {
                guard result.count >= (page.meta?.count ?? result.count) else { throw CoreError.invalid("OpenAlex returned an incomplete page sequence. Previous citation state was preserved.") }
                return result
            }
            cursor = next
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw CoreError.invalid("OpenAlex repeated a pagination cursor. Previous citation state was preserved.")
    }
    private struct WorkPage: Decodable { var results: [Work]; var meta: PageMeta? }
    private struct PageMeta: Decodable { var count: Int?; var next_cursor: String? }
    private struct Year: Decodable { var year: Int; var cited_by_count: Int }
    private struct Researcher: Decodable {
        var id: String; var display_name: String; var cited_by_count: Int; var works_count: Int; var counts_by_year: [Year]?; var summary_stats: Stats?
    }
    private struct Stats: Decodable { var h_index: Int? }
    private struct Work: Decodable {
        var id: String; var title: String?; var doi: String?; var publication_year: Int?; var cited_by_count: Int; var counts_by_year: [Year]?; var authorships: [Authorship]?; var abstract_inverted_index: [String: [Int]]?
        var publication_date: String?
        var primary_location: Location?
        var locations: [Location]?
        var metrics: CitationMetrics { .init(citationCount: cited_by_count, citationsByYear: counts_by_year?.map { .init(year: $0.year, count: $0.cited_by_count) } ?? [], provider: "OpenAlex") }
        var abstractText: String { (abstract_inverted_index ?? [:]).flatMap { token, positions in positions.map { ($0, token) } }.sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: " ") }
        var object: ResearchObject { var result = ResearchObject(title: title ?? "Untitled work", authors: authorships?.map { Author($0.author.display_name) } ?? [], year: publication_year, doi: ResearchObjectResolver.doi(doi)); result.abstract = abstractText; result.venue = primary_location?.source?.display_name ?? ""; result.sources = [.init(provider: "openalex", externalID: id, url: URL(string: id))]; return result }
    }
    private struct Location: Decodable { var is_oa: Bool?; var pdf_url: String?; var landing_page_url: String?; var version: String?; var source: LocationSource? }
    private struct LocationSource: Decodable { var type: String?; var display_name: String? }
    private struct Authorship: Decodable { var author: WorkAuthor }
    private struct WorkAuthor: Decodable { var display_name: String }
}
public enum ORCIDIdentity {
    public static func normalize(_ value: String) throws -> String {
        let stripped = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "https://orcid.org/", with: "").uppercased()
        let digits = stripped.replacingOccurrences(of: "-", with: "")
        guard digits.count == 16, digits.dropLast().allSatisfy(\.isNumber), digits.dropLast().allSatisfy({ $0.isASCII }) else { throw CoreError.invalid("Enter a valid ORCID iD, including its check digit.") }
        var total = 0; for character in digits.dropLast() { total = (total + Int(String(character))!) * 2 }
        let result = (12 - total % 11) % 11
        guard String(digits.last!) == (result == 10 ? "X" : String(result)) else { throw CoreError.invalid("The ORCID check digit does not match.") }
        return stride(from: 0, to: 16, by: 4).map { offset in String(digits.dropFirst(offset).prefix(4)) }.joined(separator: "-")
    }
}
