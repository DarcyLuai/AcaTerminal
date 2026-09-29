import Foundation

public enum ResearchMarkType: String, Codable, CaseIterable { case researchQuestion, claim, hypothesis, finding, evidence, note
    public static let arguments: [Self] = [.researchQuestion, .claim, .hypothesis, .finding]
    public var title: String { switch self { case .researchQuestion: return "Research Questions"; case .claim: return "Claims"; case .hypothesis: return "Hypotheses"; case .finding: return "Findings"; case .evidence: return "Evidence"; case .note: return "Notes" } }
}
public struct ResearchMarkLink: Codable, Hashable {
    public var targetID: String
    public var relationship: EvidenceRelationship
    public init(targetID: String, relationship: EvidenceRelationship) { self.targetID = targetID; self.relationship = relationship }
}
public struct ResearchMarkAnchor: Codable, Hashable {
    public var documentID: String?
    public var locations: [PDFTextLocation]
    public init(documentID: String?, locations: [PDFTextLocation]) { self.documentID = documentID; self.locations = locations }
}
public struct ResearchMarkEvidence: Codable, Hashable {
    public var researchObjectID: String
    public var page: String
    public var quote: String
    public var anchor: ResearchMarkAnchor
    public var sourceURL: URL?
    public var sourceReference: SourceReference?
    public init(researchObjectID: String, page: String, quote: String, anchor: ResearchMarkAnchor, sourceURL: URL? = nil, sourceReference: SourceReference? = nil) { self.researchObjectID = researchObjectID; self.page = page; self.quote = quote; self.anchor = anchor; self.sourceURL = sourceURL; self.sourceReference = sourceReference }
}
/// An interchange representation. Imported argument marks remain the SAME local Claim
/// object; MarkBinding maps its UUID to the original, document-scoped external ID.
public struct ResearchMark: Codable, Hashable, Identifiable {
    public var id: String
    public var type: ResearchMarkType
    public var text: String
    public var sourceApp: String
    public var sourceDocument: String
    public var projectID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var status: String
    public var links: [ResearchMarkLink]
    public var anchorNodeID: String?
    public var evidence: ResearchMarkEvidence?
    public init(id: String, type: ResearchMarkType, text: String, sourceApp: String, sourceDocument: String, projectID: String, createdAt: Date = Date(), updatedAt: Date = Date(), status: String = "active", links: [ResearchMarkLink] = [], anchorNodeID: String? = nil, evidence: ResearchMarkEvidence? = nil) {
        self.id = id; self.type = type; self.text = text; self.sourceApp = sourceApp; self.sourceDocument = sourceDocument; self.projectID = projectID; self.createdAt = createdAt; self.updatedAt = updatedAt; self.status = status; self.links = links; self.anchorNodeID = anchorNodeID; self.evidence = evidence
    }
    public var value: ResearchMarkValue { .init(type: type, text: text, status: status) }
}
public struct ResearchMarkValue: Codable, Hashable { public var type: ResearchMarkType; public var text: String; public var status: String
    public init(type: ResearchMarkType, text: String, status: String = "active") { self.type = type; self.text = text; self.status = status }
}
public struct ResearchMarkExchange: Codable, Equatable {
    public var schemaVersion = 1
    public var sourceApp: String
    public var projectID: String
    public var sourceDocument: String
    public var generatedAt: Date
    public var marks: [ResearchMark]
    public init(sourceApp: String, projectID: String, sourceDocument: String, marks: [ResearchMark], generatedAt: Date = Date()) { self.sourceApp = sourceApp; self.projectID = projectID; self.sourceDocument = sourceDocument; self.marks = marks; self.generatedAt = generatedAt }
    public func validate() throws {
        guard schemaVersion == 1, !sourceDocument.isEmpty, !projectID.isEmpty, marks.count <= 10000, Set(marks.map(\.id)).count == marks.count,
              marks.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 256 && $0.sourceDocument == sourceDocument && $0.projectID == projectID && $0.text.count <= 500000 && ["active", "archived", "deleted", "unresolved"].contains($0.status) }) else { throw CoreError.invalid("Invalid or unsupported Research Mark exchange. Existing research was not changed.") }
    }
}
public enum ResearchMarkCodec {
    public static func encode(_ exchange: ResearchMarkExchange) throws -> Data { try exchange.validate(); let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(exchange) }
    public static func decode(_ data: Data) throws -> ResearchMarkExchange {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { throw CoreError.invalid("Invalid interchange timestamp.") }; return date
        }
        let exchange = try decoder.decode(ResearchMarkExchange.self, from: data); try exchange.validate(); return exchange
    }
}
public struct AcaTexConnection: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var projectID: UUID
    public var documentID: String
    public var fileURL: URL
    public var lastReadAt: Date?
    public init(projectID: UUID, documentID: String, fileURL: URL) { self.projectID = projectID; self.documentID = documentID; self.fileURL = fileURL }
}
public enum ResearchSyncStatus: String, Codable { case synced, changedInAcaTex, changedInAcaTerminal, conflict, sourceMissing }
public struct MarkConflict: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var local: ResearchMarkValue
    public var remote: ResearchMarkValue
    public var detectedAt = Date()
    public var resolvedAt: Date?
}
public struct MarkBinding: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var connectionID: UUID
    public var claimID: UUID
    public var externalID: String
    public var baseline: ResearchMarkValue
    public var remote: ResearchMark
    public var state: ResearchSyncStatus
    public var conflicts: [MarkConflict] = []
    public var lastSent: ResearchMarkValue?
}
public struct EvidenceRelation: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var projectID: UUID
    public var evidenceID: UUID
    public var claimID: UUID
    public var relationship: EvidenceRelationship
    public var createdAt = Date()
    public init(projectID: UUID, evidenceID: UUID, claimID: UUID, relationship: EvidenceRelationship) { self.projectID = projectID; self.evidenceID = evidenceID; self.claimID = claimID; self.relationship = relationship }
}
public protocol ResearchMarkProjectReader { func readProject(at url: URL) throws -> ResearchMarkExchange }
public enum ResearchRoute: Equatable {
    case evidence(paperID: UUID, evidenceID: UUID)
    public var url: URL { switch self { case .evidence(let paper, let evidence): return URL(string: "acaterminal://paper/\(paper.uuidString)/evidence/\(evidence.uuidString)")! } }
    public init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == "acaterminal", url.host == "paper", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, parts.count == 3, parts[1] == "evidence", let paper = UUID(uuidString: parts[0]), let evidence = UUID(uuidString: parts[2]) else { return nil }
        self = .evidence(paperID: paper, evidenceID: evidence)
    }
    public static func acaTex(documentID: String, markID: String) -> URL {
        var parts = URLComponents(); parts.scheme = "acatex"; parts.host = "research"
        parts.queryItems = [.init(name: "document", value: documentID), .init(name: "mark", value: markID)]; return parts.url!
    }
}
public extension Claim {
    var researchType: ResearchMarkType { markType ?? .claim }
    var markValue: ResearchMarkValue { .init(type: researchType, text: text, status: markStatus ?? "active") }
}
public extension ResearchDatabase {
    func binding(for claimID: UUID) -> MarkBinding? { markBindings?.first { $0.claimID == claimID } }
    func relationship(evidenceID: UUID, claimID: UUID) -> EvidenceRelationship { evidenceRelations?.first { $0.evidenceID == evidenceID && $0.claimID == claimID }?.relationship ?? evidence.first { $0.id == evidenceID }?.relationship ?? .background }
    func syncStatus(for claimID: UUID) -> ResearchSyncStatus? {
        guard let binding = binding(for: claimID), let claim = claims.first(where: { $0.id == claimID }) else { return nil }
        if [.conflict, .sourceMissing].contains(binding.state) { return binding.state }
        return claim.markValue != binding.baseline ? .changedInAcaTerminal : binding.state
    }
    mutating func ingestMarks(_ exchange: ResearchMarkExchange, connectionID: UUID) throws {
        try exchange.validate()
        guard let connection = acaTexConnections?.first(where: { $0.id == connectionID }), connection.documentID == exchange.sourceDocument else { throw CoreError.invalid("The AcaTex document identity changed. Connect it as a separate project.") }
        var bindings = markBindings ?? []
        var claimIndex = Dictionary(uniqueKeysWithValues: claims.enumerated().map { ($0.element.id, $0.offset) })
        var bindingIndex = Dictionary(uniqueKeysWithValues: bindings.enumerated().filter { $0.element.connectionID == connectionID }.map { ($0.element.externalID, $0.offset) })
        let incoming = exchange.marks.filter { ResearchMarkType.arguments.contains($0.type) }
        for remote in incoming {
            if let b = bindingIndex[remote.id], let c = claimIndex[bindings[b].claimID] {
                let local = claims[c].markValue, baseline = bindings[b].baseline
                bindings[b].remote = remote
                if ["deleted", "unresolved"].contains(remote.status) { bindings[b].state = .sourceMissing; continue }
                if local == remote.value { bindings[b].baseline = remote.value; bindings[b].state = .synced }
                else if local == baseline {
                    claims[c].text = remote.text; claims[c].markType = remote.type; claims[c].markStatus = remote.status; claims[c].updatedAt = remote.updatedAt
                    bindings[b].baseline = remote.value; bindings[b].state = .changedInAcaTex
                } else if remote.value == baseline { bindings[b].state = .changedInAcaTerminal }
                else {
                    bindings[b].state = .conflict
                    if !bindings[b].conflicts.contains(where: { $0.local == local && $0.remote == remote.value && $0.resolvedAt == nil }) { bindings[b].conflicts.append(.init(local: local, remote: remote.value)) }
                }
            } else {
                var claim = Claim(projectID: connection.projectID, text: remote.text)
                // UUIDs are retained when safe; non-UUID external IDs remain intact in the binding.
                if let id = UUID(uuidString: remote.id), claimIndex[id] == nil { claim.id = id }
                claim.markType = remote.type; claim.markStatus = remote.status; claim.createdAt = remote.createdAt; claim.updatedAt = remote.updatedAt; claimIndex[claim.id] = claims.count; claims.append(claim)
                bindingIndex[remote.id] = bindings.count
                bindings.append(.init(connectionID: connectionID, claimID: claim.id, externalID: remote.id, baseline: remote.value, remote: remote, state: ["deleted", "unresolved"].contains(remote.status) ? .sourceMissing : .synced))
            }
        }
        let ids = Set(incoming.map(\.id))
        for i in bindings.indices where bindings[i].connectionID == connectionID && !ids.contains(bindings[i].externalID) { bindings[i].state = bindings[i].remote.sourceApp == "AcaTerminal" && bindings[i].lastSent != nil ? .changedInAcaTerminal : .sourceMissing }
        markBindings = bindings
        if let index = acaTexConnections?.firstIndex(where: { $0.id == connectionID }) { acaTexConnections?[index].lastReadAt = exchange.generatedAt }
    }
    mutating func resolveMarkConflict(_ claimID: UUID, useRemote: Bool) throws {
        guard let b = markBindings?.firstIndex(where: { $0.claimID == claimID }), let c = claims.firstIndex(where: { $0.id == claimID }), let remote = markBindings?[b].remote else { throw CoreError.invalid("Research mark not found.") }
        if useRemote { claims[c].text = remote.text; claims[c].markType = remote.type; claims[c].markStatus = remote.status; claims[c].updatedAt = Date() }
        markBindings?[b].baseline = remote.value; markBindings?[b].state = useRemote ? .synced : .changedInAcaTerminal
        for i in (markBindings?[b].conflicts ?? []).indices where markBindings?[b].conflicts[i].resolvedAt == nil { markBindings?[b].conflicts[i].resolvedAt = Date() }
    }
    mutating func exportMarks(connectionID: UUID, claimIDs: Set<UUID>) throws -> ResearchMarkExchange {
        guard let connection = acaTexConnections?.first(where: { $0.id == connectionID }) else { throw CoreError.invalid("Connect an AcaTex project first.") }
        var result: [ResearchMark] = []
        for claim in claims where claim.projectID == connection.projectID && claimIDs.contains(claim.id) {
            guard syncStatus(for: claim.id) != .conflict && syncStatus(for: claim.id) != .sourceMissing else { throw CoreError.invalid("Resolve the conflict or missing source before sending this mark.") }
            let binding = binding(for: claim.id)
            let id = binding?.externalID ?? claim.id.uuidString
            let mark = ResearchMark(id: id, type: claim.researchType, text: claim.text, sourceApp: "AcaTerminal", sourceDocument: connection.documentID, projectID: connection.documentID, createdAt: claim.createdAt, updatedAt: claim.updatedAt, status: claim.markStatus ?? "active", anchorNodeID: binding?.remote.anchorNodeID)
            result.append(mark)
            if let b = markBindings?.firstIndex(where: { $0.claimID == claim.id }) { markBindings?[b].lastSent = claim.markValue }
            else { markBindings = (markBindings ?? []) + [.init(connectionID: connectionID, claimID: claim.id, externalID: id, baseline: claim.markValue, remote: mark, state: .changedInAcaTerminal, lastSent: claim.markValue)] }
            for evidence in evidence where claim.evidence.contains(evidence.id) {
                let source = objects.first { $0.id == evidence.paperID }?.sources.first { $0.provider == "local-pdf" || $0.provider == "local-document" }
                let link = ResearchMarkLink(targetID: id, relationship: relationship(evidenceID: evidence.id, claimID: claim.id))
                if let existing = result.firstIndex(where: { $0.id == evidence.id.uuidString }) { result[existing].links.append(link) }
                else { result.append(ResearchMark(id: evidence.id.uuidString, type: .evidence, text: evidence.note, sourceApp: "AcaTerminal", sourceDocument: connection.documentID, projectID: connection.documentID, createdAt: evidence.createdAt, links: [link], evidence: .init(researchObjectID: evidence.paperID.uuidString, page: evidence.page, quote: evidence.quote, anchor: .init(documentID: evidence.documentID, locations: evidence.locations ?? []), sourceURL: ResearchRoute.evidence(paperID: evidence.paperID, evidenceID: evidence.id).url, sourceReference: source))) }
            }
        }
        return ResearchMarkExchange(sourceApp: "AcaTerminal", projectID: connection.documentID, sourceDocument: connection.documentID, marks: result)
    }
    func validateResearchMarks() throws {
        let connections = acaTexConnections ?? [], bindings = markBindings ?? [], relations = evidenceRelations ?? []
        guard Set(connections.map(\.id)).count == connections.count, Set(connections.map(\.documentID)).count == connections.count, Set(connections.map(\.projectID)).count == connections.count,
              connections.allSatisfy({ connection in projects.contains(where: { $0.id == connection.projectID }) && connection.fileURL.isFileURL && !connection.documentID.isEmpty }),
              Set(bindings.map(\.claimID)).count == bindings.count, Set(bindings.map { $0.connectionID.uuidString + "|" + $0.externalID }).count == bindings.count else { throw CoreError.invalid("Invalid AcaTex connection identity.") }
        for binding in bindings { guard let connection = connections.first(where: { $0.id == binding.connectionID }), claims.contains(where: { $0.id == binding.claimID && $0.projectID == connection.projectID }), !binding.externalID.isEmpty else { throw CoreError.invalid("Invalid research mark binding.") } }
        guard Set(relations.map { $0.evidenceID.uuidString + $0.claimID.uuidString }).count == relations.count else { throw CoreError.invalid("Duplicate evidence relationship.") }
        for link in relations { guard let claim = claims.first(where: { $0.id == link.claimID }), claim.projectID == link.projectID, claim.evidence.contains(link.evidenceID), evidence.contains(where: { $0.id == link.evidenceID && $0.projectID == link.projectID }) else { throw CoreError.invalid("Invalid evidence relationship.") } }
    }
}
