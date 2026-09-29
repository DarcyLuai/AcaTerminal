import Foundation

public struct ReadingPosition: Codable, Equatable, Identifiable {
    public var id: UUID { paperID }
    public var paperID: UUID
    public var documentID: String
    /// Zero-based physical PDF page, independent of printed page labels.
    public var page: Int
    public var pageCount: Int
    public var normalizedScrollPosition: Double
    public var normalizedHorizontalPosition: Double
    public var zoom: Double
    /// Optional viewport-relative magnification; old records retain physical PDF zoom.
    public var readingScale: Double?
    public var readerMode: String
    public var lastOpenedAt: Date
    public var markedRead: Bool
    public init(paperID: UUID, documentID: String, page: Int = 0, pageCount: Int = 1, normalizedScrollPosition: Double = 0, normalizedHorizontalPosition: Double = 0, zoom: Double = 1, readerMode: String = "continuous", markedRead: Bool = false) {
        self.paperID = paperID; self.documentID = documentID
        self.pageCount = max(1, pageCount); self.page = min(max(0, page), max(0, pageCount - 1))
        self.normalizedScrollPosition = normalizedScrollPosition.isFinite ? min(1, max(0, normalizedScrollPosition)) : 0
        self.normalizedHorizontalPosition = normalizedHorizontalPosition.isFinite ? min(1, max(0, normalizedHorizontalPosition)) : 0
        self.zoom = zoom.isFinite ? min(8, max(0.1, zoom)) : 1
        self.readerMode = readerMode; self.lastOpenedAt = Date(); self.markedRead = markedRead
    }
    public var progress: Int { markedRead ? 100 : min(99, max(0, Int((Double(page) + normalizedScrollPosition) / Double(max(1, pageCount)) * 100))) }
}
public struct PDFTextLocation: Codable, Hashable {
    public var page: Int
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(page: Int, x: Double, y: Double, width: Double, height: Double) { self.page = page; self.x = x; self.y = y; self.width = width; self.height = height }
}
public struct ReaderHighlight: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var paperID: UUID
    public var documentID: String
    public var quote: String
    public var locations: [PDFTextLocation]
    public var createdAt = Date()
    public init(paperID: UUID, documentID: String, quote: String, locations: [PDFTextLocation]) { self.paperID = paperID; self.documentID = documentID; self.quote = quote; self.locations = locations }
}
public extension ResearchDatabase {
    func readingPosition(for paperID: UUID) -> ReadingPosition? { readingStates?.first { $0.paperID == paperID } }
    mutating func savePosition(_ position: ReadingPosition) {
        var states = readingStates ?? []
        if let i = states.firstIndex(where: { $0.paperID == position.paperID }) { states[i] = position } else { states.append(position) }
        readingStates = states
    }
    mutating func saveEvidence(_ item: Evidence, projectID: UUID, claimID: UUID? = nil) throws {
        guard projects.contains(where: { $0.id == projectID }), let p = objects.firstIndex(where: { $0.id == item.paperID }), !evidence.contains(where: { $0.id == item.id }) else { throw CoreError.invalid("Choose an existing paper and project.") }
        if let claimID = claimID { guard claims.contains(where: { $0.id == claimID && $0.projectID == projectID }) else { throw CoreError.invalid("Choose a claim from this project.") } }
        var item = item; item.projectID = projectID; evidence.append(item)
        if !objects[p].projects.contains(projectID) { objects[p].projects.append(projectID) }
        if let claimID = claimID { try attachEvidence(item.id, to: claimID) }
    }
    mutating func attachEvidence(_ evidenceID: UUID, to claimID: UUID, relationship: EvidenceRelationship? = nil) throws {
        guard let e = evidence.firstIndex(where: { $0.id == evidenceID }), let c = claims.firstIndex(where: { $0.id == claimID }) else { throw CoreError.invalid("Evidence or claim is no longer available.") }
        guard evidence[e].projectID == nil || evidence[e].projectID == claims[c].projectID else { throw CoreError.invalid("Evidence and claim must belong to the same project.") }
        evidence[e].projectID = claims[c].projectID
        if !claims[c].evidence.contains(evidenceID) { claims[c].evidence.append(evidenceID) }
        if !claims[c].sources.contains(evidence[e].paperID) { claims[c].sources.append(evidence[e].paperID) }
        let relation = relationship ?? evidence[e].relationship
        if let index = evidenceRelations?.firstIndex(where: { $0.evidenceID == evidenceID && $0.claimID == claimID }) { if let relationship = relationship { evidenceRelations?[index].relationship = relationship } }
        else { evidenceRelations = (evidenceRelations ?? []) + [.init(projectID: claims[c].projectID, evidenceID: evidenceID, claimID: claimID, relationship: relation)] }
        claims[c].updatedAt = Date()
        if let p = objects.firstIndex(where: { $0.id == evidence[e].paperID }), !objects[p].projects.contains(claims[c].projectID) { objects[p].projects.append(claims[c].projectID) }
    }
    mutating func upgradeReadingFormat() throws {
        guard (1...5).contains(formatVersion) else { throw CoreError.invalid("Unsupported workspace format. Your data has not been changed.") }
        // Optional additions decode old payloads. Do not invent project ownership for
        // legacy evidence shared across multiple projects.
        if formatVersion == 1 {
            for i in evidence.indices where evidence[i].projectID == nil {
                let owners = Set(claims.filter { $0.evidence.contains(evidence[i].id) }.map(\.projectID))
                if owners.count == 1 { evidence[i].projectID = owners.first }
            }
            formatVersion = 2
        }
        if formatVersion == 2 {
            if let identity = identity { adoptIdentity(identity) }
            citationEvents = citationEvents ?? []; citationStates = citationStates ?? []
            impactRefresh = impactRefresh ?? ImpactRefreshState(); formatVersion = 3
        }
        if formatVersion == 3 {
            claimRelations = claimRelations ?? []; discoveryCaches = discoveryCaches ?? []
            discoveryFeedback = discoveryFeedback ?? []; literatureSnapshots = literatureSnapshots ?? []
            literatureChanges = literatureChanges ?? []; formatVersion = 4
        }
        if formatVersion == 4 {
            acaTexConnections = acaTexConnections ?? []; markBindings = markBindings ?? []; evidenceRelations = evidenceRelations ?? []
            for claim in claims { for id in Set(claim.evidence) {
                if let item = evidence.first(where: { $0.id == id }), item.projectID == claim.projectID, !(evidenceRelations ?? []).contains(where: { $0.evidenceID == id && $0.claimID == claim.id }) {
                    evidenceRelations?.append(.init(projectID: claim.projectID, evidenceID: id, claimID: claim.id, relationship: item.relationship))
                }
            } }
            formatVersion = 5
        }

    }
}
