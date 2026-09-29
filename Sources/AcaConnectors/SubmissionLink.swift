import Foundation
import AcaCore

public struct SubmissionLink: Equatable {
    public var url: URL
    public var platform: String
    public var openReviewID: String?
    public static func parse(_ input: String) throws -> Self {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value), let url = components.url, components.scheme?.lowercased() == "https", let host = components.host?.lowercased(), host.contains("."), components.user == nil, components.password == nil, components.port == nil || components.port == 443,
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "localhost", host.range(of: #"^[0-9.:]+$"#, options: .regularExpression) == nil else { throw CoreError.invalid("Enter a public HTTPS submission URL without login credentials.") }
        func belongs(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        let platform = belongs("openreview.net") ? "OpenReview" : belongs("editorialmanager.com") ? "Editorial Manager" : belongs("manuscriptcentral.com") ? "ScholarOne" : belongs("wiley.com") ? "Wiley" : belongs("nature.com") || belongs("mts-nature.nature.com") ? "Nature" : belongs("acs.org") ? "ACS" : belongs("ieee.org") ? "IEEE" : "Website"
        let ids = components.queryItems?.filter { $0.name == "id" }.compactMap(\.value) ?? []
        let id = platform == "OpenReview" && components.path == "/forum" && ids.count == 1 && ids[0].range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil ? ids[0] : nil
        return Self(url: url, platform: platform, openReviewID: id)
    }
}
public struct SubmissionLinkResult {
    public var link: SubmissionLink
    public var title: String?
    public var journal: String?
    public var externalID: String?
    public var submittedAt: Date?
    public var statusRaw: String?
    public var status: SubmissionStatus?
    public var notice: String
    public var statusSource: String { statusRaw == nil ? "manual" : "openreview" }
}
public struct SubmissionLinkProvider {
    let transport: HTTPTransport
    public init(transport: HTTPTransport = HTTPClient()) { self.transport = transport }
    public func lookup(_ input: String) async throws -> SubmissionLinkResult {
        let link = try SubmissionLink.parse(input)
        var result = SubmissionLinkResult(link: link, notice: "Website recognized. Supplement the details below; private status requires the journal portal.")
        if let id = link.openReviewID {
            let data = try await get("https://api2.openreview.net/notes", query: [.init(name: "id", value: id)])
            let notes = try decodeNotes(data)
            guard let note = notes.first(where: { $0["id"] as? String == id }), note["readers"] as? [String] == ["everyone"] else { throw CoreError.invalid("This OpenReview submission is not publicly readable.") }
            let content = note["content"] as? [String: Any] ?? [:]
            result.title = field(content, "title"); result.journal = field(content, "venue"); result.externalID = id
            // cdate can be backdated and odate is public release time, neither proves submission time.
            result.notice = "Public metadata retrieved. No public decision is available; the status remains unknown."
            let replies = try await get("https://api2.openreview.net/notes", query: [.init(name: "forum", value: id), .init(name: "limit", value: "1000")])
            let decisions = try decodeNotes(replies).filter { note in
                (note["invitations"] as? [String] ?? []).contains { $0.hasSuffix("/-/Decision") } && note["readers"] as? [String] == ["everyone"]
            }.sorted { ($0["tmdate"] as? Double ?? 0) > ($1["tmdate"] as? Double ?? 0) }
            if let decision = decisions.first, let raw = field(decision["content"] as? [String: Any] ?? [:], "decision") {
                result.statusRaw = raw
                let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                result.status = lower.hasPrefix("accept") ? .accepted : lower.hasPrefix("reject") ? .rejected : .normalize(raw)
                result.notice = "Public metadata and decision retrieved from OpenReview."
            }
            return result
        }
        if link.platform != "Website" { return result }
        // Read public bibliographic metadata only; never infer review state from arbitrary page text.
        var request = URLRequest(url: link.url); request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await transport.data(for: request)
        guard data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) else { return result }
        result.title = meta("citation_title", html: html)
        result.journal = meta("citation_journal_title", html: html)
        if result.title != nil || result.journal != nil { result.notice = "Public bibliographic details retrieved. Review status must be supplied separately." }
        return result
    }
    private func get(_ address: String, query: [URLQueryItem]) async throws -> Data {
        var parts = URLComponents(string: address)!; parts.queryItems = query
        var request = URLRequest(url: parts.url!); request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await transport.data(for: request)
    }
    private func decodeNotes(_ data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let notes = json["notes"] as? [[String: Any]] else { throw CoreError.invalid("The service returned an invalid response.") }
        guard (json["count"] as? Int ?? notes.count) <= 1000 else { throw CoreError.invalid("This forum has too many replies to identify its latest decision safely.") }
        return notes
    }
    private func field(_ content: [String: Any], _ key: String) -> String? {
        let string = (content[key] as? [String: Any])?["value"] as? String ?? content[key] as? String
        return string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? string : nil
    }
    private func meta(_ name: String, html: String) -> String? {
        let tags = try? NSRegularExpression(pattern: "<meta\\s[^>]*>", options: .caseInsensitive)
        for match in tags?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            let tag = (html as NSString).substring(with: match.range)
            let attrs = try? NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*["']([^"']*)["']"#)
            var values: [String: String] = [:]
            for item in attrs?.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) ?? [] { values[(tag as NSString).substring(with: item.range(at: 1)).lowercased()] = (tag as NSString).substring(with: item.range(at: 2)) }
            if values["name"]?.lowercased() == name, let value = values["content"], !value.isEmpty { return value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'") }
        }
        return nil
    }
}
