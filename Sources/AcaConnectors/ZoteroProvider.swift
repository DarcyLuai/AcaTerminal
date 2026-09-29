import Foundation
import AcaCore
public struct ZoteroProvider: LibraryProvider {
    public let identifier = "zotero"
    public let displayName = "Zotero"
    private let base: URL
    private let prefix: String
    private let key: String?
    private let transport: HTTPTransport
    public init(local: Bool, userID: String = "0", apiKey: String? = nil, transport: HTTPTransport = HTTPClient()) throws {
        guard local || (!userID.isEmpty && userID.allSatisfy(\.isNumber)) else { throw CoreError.invalid("Zotero requires a numeric user ID, not your username.") }
        base = URL(string: local ? "http://127.0.0.1:23119/api/" : "https://api.zotero.org/")!
        prefix = "users/\(local ? "0" : userID)"; key = local ? nil : apiKey; self.transport = transport
    }
    private var scope: String { (base.scheme == "http" ? "local:" : "web:") + prefix }
    public func importLibrary() async throws -> LibraryImport {
        let collectionRows: [CollectionRow] = try await pages("collections")
        let rows: [ItemRow] = try await pages("items")
        let collections = collectionRows.map { LibraryCollection(id: scope + ":" + $0.key, name: $0.data.name, parentID: $0.data.parentCollection.string.map { scope + ":" + $0 }) }
        var objects: [ResearchObject] = []; var idMap: [String: UUID] = [:]
        for row in rows where row.data.itemType != "note" && row.data.itemType != "attachment" {
            let item = row.data
            let authors = (item.creators ?? []).filter { ["author", "bookAuthor", "editor", "programmer"].contains($0.creatorType ?? "author") }.map { Author($0.name ?? [$0.firstName, $0.lastName].compactMap { $0 }.joined(separator: " ")) }
            let year = item.date.flatMap { value -> Int? in guard let range = value.range(of: #"\b(1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b"#, options: .regularExpression) else { return nil }; return Int(value[range]) }
            var object = ResearchObject(title: item.title ?? "Untitled item", authors: authors, year: year, doi: ResearchObjectResolver.doi(item.DOI))
            object.type = item.itemType == "book" ? .book : item.itemType == "dataset" ? .dataset : item.itemType == "computerProgram" ? .code : item.itemType == "manuscript" ? .manuscript : .paper
            object.isbn = item.ISBN; object.venue = item.publicationTitle ?? item.publisher ?? ""; object.abstract = item.abstractNote ?? ""; object.tags = (item.tags ?? []).map(\.tag)
            if let archive = item.archiveID, item.archive?.lowercased().contains("arxiv") == true { object.arxivID = ResearchObjectResolver.arxiv(archive) }
            object.sources = [.init(provider: "zotero", externalID: scope + ":" + row.key, url: URL(string: "zotero://select/library/items/\(row.key)"), metadata: ["collections": (item.collections ?? []).map { scope + ":" + $0 }.joined(separator: ","), "version": String(row.version ?? 0)])]
            idMap[row.key] = object.id; objects.append(object)
        }
        for row in rows where row.data.itemType == "attachment" && row.data.contentType == "application/pdf" && row.data.linkMode != "linked_url" {
            let source = SourceReference(provider: "zotero-pdf", externalID: scope + ":" + row.key, metadata: ["md5": row.data.md5 ?? "", "version": String(row.version ?? 0), "filename": row.data.filename ?? "attachment.pdf"])
            if let parent = row.data.parentItem, let id = idMap[parent], let index = objects.firstIndex(where: { $0.id == id }) { objects[index].sources.append(source) }
            else if row.data.parentItem == nil { var object = ResearchObject(title: row.data.title ?? "Zotero PDF"); object.sources = [source]; objects.append(object) }
        }
        var notes: [ResearchNote] = []
        for row in rows where row.data.itemType == "note" {
            let text = Self.plainText(row.data.note ?? "")
            if let parent = row.data.parentItem, let id = idMap[parent] { notes.append(.init(paperID: id, text: text, sourceID: scope + ":" + row.key)) }
            else {
                var object = ResearchObject(title: String(text.prefix(100))); object.type = .note; object.abstract = text
                object.sources = [.init(provider: "zotero", externalID: scope + ":" + row.key)]; objects.append(object)
            }
        }
        return .init(objects: objects, notes: notes, collections: collections)
    }
    private func pages<T: Decodable>(_ endpoint: String) async throws -> [T] {
        var result: [T] = []
        for page in 0..<1000 {
            try Task.checkCancellation()
            var components = URLComponents(url: base.appendingPathComponent(prefix + "/" + endpoint), resolvingAgainstBaseURL: false)!
            components.queryItems = [.init(name: "format", value: "json"), .init(name: "limit", value: "100"), .init(name: "start", value: String(page * 100))]
            var request = URLRequest(url: components.url!); request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
            if let key = key, !key.isEmpty { request.setValue(key, forHTTPHeaderField: "Zotero-API-Key") }
            let rows = try JSONDecoder().decode([T].self, from: await transport.data(for: request)); result += rows
            if rows.count < 100 { return result }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw CoreError.invalid("This library exceeds the v0.1 import limit (100,000 records). No partial import was saved.")
    }
    public static func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>|<br\s*/?>|</div>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private struct ItemRow: Decodable { var key: String; var version: Int?; var data: Item }
    private struct Item: Decodable {
        var contentType: String?; var linkMode: String?; var md5: String?; var filename: String?
        var itemType: String; var title: String?; var creators: [Creator]?; var DOI: String?; var ISBN: String?; var date: String?; var publicationTitle: String?; var publisher: String?; var abstractNote: String?; var tags: [Tag]?; var collections: [String]?; var parentItem: String?; var note: String?; var archive: String?; var archiveID: String?
    }
    private struct Creator: Decodable { var firstName: String?; var lastName: String?; var name: String?; var creatorType: String? }
    private struct Tag: Decodable { var tag: String }
    private struct CollectionRow: Decodable { var key: String; var data: CollectionData }
    private struct CollectionData: Decodable { var name: String; var parentCollection: StringOrFalse }
    private struct StringOrFalse: Decodable {
        var string: String?
        init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); string = try? c.decode(String.self) }
    }
}
