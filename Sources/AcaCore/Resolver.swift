import Foundation
public enum Resolution: Equatable { case match(UUID), possible([UUID]), new }
public struct ResearchObjectResolver {
    public init() {}
    public static func doi(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:"] { if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) } }
        let normalized = (text.removingPercentEncoding ?? text).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
    public static func arxiv(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        for prefix in ["https://arxiv.org/abs/", "http://arxiv.org/abs/", "https://arxiv.org/pdf/", "arxiv:"] { if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) } }
        return text.replacingOccurrences(of: #"(\.pdf)?$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }
    public static func isbn(_ value: String?) -> String? {
        guard let value = value else { return nil }; let result = value.uppercased().filter { $0.isNumber || $0 == "X" }; return result.isEmpty ? nil : result
    }
    private func text(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
    public func resolve(_ object: ResearchObject, in existing: [ResearchObject]) -> Resolution {
        // Provider IDs make repeated imports idempotent, but never override conflicting DOIs.
        let sourceMatches = existing.filter { item in object.sources.contains { source in item.sources.contains { $0.id == source.id } } }
        for key in [Self.doi, Self.arxiv, Self.isbn].indices {
            let getter: (ResearchObject) -> String? = key == 0 ? { Self.doi($0.doi) } : key == 1 ? { Self.arxiv($0.arxivID) } : { Self.isbn($0.isbn) }
            if let id = getter(object) {
                let hits = existing.filter { getter($0) == id }
                if !hits.isEmpty {
                    let conflicts = hits.contains { old in
                        if key > 0, let a = Self.doi(old.doi), let b = Self.doi(object.doi), a != b { return true }
                        if key > 1, let a = Self.arxiv(old.arxivID), let b = Self.arxiv(object.arxivID), a != b { return true }
                        return false
                    }
                    return hits.count == 1 && !conflicts ? .match(hits[0].id) : .possible(hits.map(\.id))
                }
            }
        }
        if sourceMatches.count == 1 {
            let old = sourceMatches[0]
            if let a = Self.doi(old.doi), let b = Self.doi(object.doi), a != b { return .possible([old.id]) }
            return .match(old.id)
        }
        if sourceMatches.count > 1 { return .possible(sourceMatches.map(\.id)) }
        guard !object.title.isEmpty, let year = object.year, let author = object.authors.first, !author.name.isEmpty else { return .new }
        let hits = existing.filter { $0.type == object.type && $0.year == year && text($0.title) == text(object.title) && $0.authors.first.map { text($0.name) } == text(author.name) }
        return hits.isEmpty ? .new : .possible(hits.map(\.id))
    }
    public func merge(_ incoming: ResearchObject, into existing: ResearchObject) -> ResearchObject {
        var result = existing
        result.doi = existing.doi ?? incoming.doi; result.arxivID = existing.arxivID ?? incoming.arxivID; result.isbn = existing.isbn ?? incoming.isbn
        if result.abstract.isEmpty { result.abstract = incoming.abstract }; if result.venue.isEmpty { result.venue = incoming.venue }
        if result.authors.isEmpty { result.authors = incoming.authors }; result.year = existing.year ?? incoming.year
        for source in incoming.sources {
            if let i = result.sources.firstIndex(where: { $0.id == source.id }) { result.sources[i] = source } else { result.sources.append(source) }
        }
        result.tags = Array(Set(result.tags + incoming.tags)).sorted(); result.projects = Array(Set(result.projects + incoming.projects)); result.updatedAt = Date()
        return result
    }
}
