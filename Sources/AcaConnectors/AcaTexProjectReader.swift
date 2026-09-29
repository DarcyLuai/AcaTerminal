import Foundation
import AcaCore

/// Independently implemented against the native AcaTeX 0.8.6 document contract.
/// Reads only the selected local document; never crawls attachments or invokes a URL.
public struct AcaTexProjectReader: ResearchMarkProjectReader {
    public init() {}
    public func readProject(at url: URL) throws -> ResearchMarkExchange {
        guard url.isFileURL else { throw CoreError.invalid("Choose a local AcaTex project.") }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100_000_000 else { throw CoreError.invalid("The AcaTex project exceeds the 100 MB import limit.") }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }
    public func decode(_ data: Data) throws -> ResearchMarkExchange {
        guard data.count <= 100_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoreError.invalid("Invalid AcaTex project.") }
        if root["schemaVersion"] != nil { return try ResearchMarkCodec.decode(data) }
        guard let content = root["content"] as? [String: Any], content["type"] as? String == "doc", let attrs = content["attrs"] as? [String: Any], let documentID = (attrs["documentId"] ?? root["documentId"]) as? String, !documentID.isEmpty,
              let rawMarks = attrs["researchObjects"] as? [[String: Any]], rawMarks.count <= 10000 else { throw CoreError.invalid("This project has no supported stable Research Mark document identity. Save it in a current AcaTex first.") }
        if let outer = root["documentId"] as? String, outer != documentID { throw CoreError.invalid("AcaTex document identities disagree.") }
        var nodes: [String: String] = [:], count = 0
        func text(_ node: [String: Any], depth: Int) throws -> String {
            guard depth < 100, count < 200000 else { throw CoreError.invalid("AcaTex document nesting or size exceeds the import limit.") }; count += 1
            var value = node["text"] as? String ?? ""
            for child in node["content"] as? [[String: Any]] ?? [] { value += try text(child, depth: depth + 1) }
            if let id = (node["attrs"] as? [String: Any])?["nodeId"] as? String {
                guard nodes[id] == nil else { throw CoreError.invalid("Duplicate AcaTex anchor ID.") }; nodes[id] = value
            }
            return value
        }
        _ = try text(content, depth: 0)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var marks: [ResearchMark] = []
        for raw in rawMarks {
            guard let id = raw["id"] as? String, !id.isEmpty, let type = (raw["type"] as? String).flatMap(ResearchMarkType.init(rawValue:)), ResearchMarkType.arguments.contains(type), let anchor = raw["anchorNodeId"] as? String, !anchor.isEmpty else { throw CoreError.invalid("AcaTex contains an unsupported or unstable research mark.") }
            let created = (raw["createdAt"] as? String).flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date(timeIntervalSince1970: 0)
            marks.append(.init(id: id, type: type, text: nodes[anchor] ?? "", sourceApp: "AcaTex", sourceDocument: documentID, projectID: documentID, createdAt: created, status: nodes[anchor] == nil ? "unresolved" : "active", anchorNodeID: anchor))
        }
        let result = ResearchMarkExchange(sourceApp: "AcaTex", projectID: documentID, sourceDocument: documentID, marks: marks); try result.validate(); return result
    }
}
