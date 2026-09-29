import Foundation
import AcaCore

public struct LocalFullTextProvider: FullTextProvider {
    public let identifier = "local"; public let displayName = "Local"
    public init() {}
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        object.sources.filter { $0.provider == "local-pdf" && $0.url?.isFileURL == true && FileManager.default.fileExists(atPath: $0.url!.path) }.map { .init(provider: $0.metadata["fullTextProvider"] ?? displayName, url: $0.url!, accessType: .local, version: PaperVersion(rawValue: $0.metadata["paperVersion"] ?? "") ?? .unknown, isDirectPDF: true, sourceID: $0.id, hostType: $0.metadata["hostType"]) }
    }
}
public struct ZoteroFullTextProvider: FullTextProvider {
    public let identifier = "zotero"; public let displayName = "Zotero"
    public init() {}
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        try object.sources.filter { $0.provider == "zotero-pdf" }.map { .init(provider: displayName, url: try ZoteroAttachment.endpoint(for: $0), accessType: .library, isDirectPDF: true, sourceID: $0.id) }
    }
}
public struct ArxivFullTextProvider: FullTextProvider {
    public let identifier = "arxiv"; public let displayName = "arXiv"
    public init() {}
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        guard var id = object.arxivID else { return [] }
        id = id.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "https://arxiv.org/abs/", with: "").replacingOccurrences(of: "arXiv:", with: "")
        guard id.range(of: #"^([0-9]{4}\.[0-9]{4,5}|[a-zA-Z-]+(\.[A-Z]{2})?/[0-9]{7})(v[0-9]+)?$"#, options: .regularExpression) != nil, let url = URL(string: "https://arxiv.org/pdf/" + id) else { throw CoreError.invalid("Invalid arXiv identifier.") }
        return [.init(provider: displayName, url: url, accessType: .openAccess, version: .preprint, isDirectPDF: true, hostType: "repository")]
    }
}
public struct UnpaywallFullTextProvider: FullTextProvider {
    public let identifier = "unpaywall"; public let displayName = "Unpaywall"
    let email: String; let transport: HTTPTransport
    public init(email: String, transport: HTTPTransport = HTTPClient()) { self.email = email; self.transport = transport }
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        guard let doi = ResearchObjectResolver.doi(object.doi) else { return [] }
        guard email.contains("@"), !email.contains(" ") else { throw CoreError.invalid("Add a contact email in Settings to use Unpaywall.") }
        var parts = URLComponents(); parts.scheme = "https"; parts.host = "api.unpaywall.org"; parts.path = "/v2/" + doi; parts.queryItems = [.init(name: "email", value: email)]
        let data = try await transport.data(for: URLRequest(url: parts.url!))
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.oa_locations ?? []).compactMap { location in
            guard let url = (location.url_for_pdf ?? location.url_for_landing_page).flatMap(URL.init(string:)), url.scheme == "https" else { return nil }
            return .init(provider: displayName, url: url, accessType: .openAccess, version: .init(apiValue: location.version), isDirectPDF: location.url_for_pdf != nil, hostType: location.host_type)
        }
    }
    private struct Response: Decodable { var oa_locations: [Location]? }
    private struct Location: Decodable { var url_for_pdf: String?; var url_for_landing_page: String?; var version: String?; var host_type: String? }
}
public struct PublisherFullTextProvider: FullTextProvider {
    public let identifier = "publisher"; public let displayName = "Publisher"
    public init() {}
    public func resolve(_ object: ResearchObject) async throws -> [FullTextLocation] {
        var result: [FullTextLocation] = []
        for source in object.sources where source.url?.scheme == "https" {
            guard let url = source.url, let host = url.host else { continue }
            if host == "jstor.org" || host.hasSuffix(".jstor.org") { result.append(.init(provider: "JSTOR", url: url, accessType: .institutional, isDirectPDF: false)) }
            else if source.provider == "publisher" { result.append(.init(provider: displayName, url: url, accessType: .landingPage, isDirectPDF: false)) }
        }
        if let doi = ResearchObjectResolver.doi(object.doi), let url = URL(string: "https://doi.org/" + doi) { result.append(.init(provider: displayName, url: url, accessType: .landingPage, isDirectPDF: false)) }
        return result
    }
}
