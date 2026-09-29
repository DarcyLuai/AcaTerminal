import Foundation

public enum ClaimRelationship: String, Codable, CaseIterable {
    case supports, contradicts, extends, qualifies, dependsOn
}
public struct ClaimRelation: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var projectID: UUID
    public var sourceClaimID: UUID
    public var targetClaimID: UUID
    public var relationship: ClaimRelationship
    public var createdAt = Date()
    public init(projectID: UUID, sourceClaimID: UUID, targetClaimID: UUID, relationship: ClaimRelationship) {
        self.projectID = projectID; self.sourceClaimID = sourceClaimID; self.targetClaimID = targetClaimID; self.relationship = relationship
    }
    public var key: String { "\(sourceClaimID)|\(targetClaimID)|\(relationship.rawValue)" }
}
public struct ClaimGraph {
    public enum Kind: String { case claim, evidence, paper }
    public struct Node: Identifiable { public var id: UUID; public var kind: Kind; public var text: String }
    public struct Edge: Identifiable {
        public var id: String { "\(source)|\(target)|\(label)" }
        public var source: UUID; public var target: UUID; public var label: String
    }
    public var nodes: [Node]
    public var edges: [Edge]
    public init(database: ResearchDatabase, projectID: UUID) {
        let claims = database.claims.filter { $0.projectID == projectID }
        let linked = Set(claims.flatMap(\.evidence))
        let evidence = database.evidence.filter { $0.projectID == projectID || linked.contains($0.id) }
        let paperIDs = Set(evidence.map(\.paperID) + claims.flatMap(\.sources))
        let papers = database.objects.filter { paperIDs.contains($0.id) }
        nodes = claims.map { Node(id: $0.id, kind: .claim, text: $0.text) } + evidence.map { Node(id: $0.id, kind: .evidence, text: $0.quote.isEmpty ? $0.note : $0.quote) } + papers.map { Node(id: $0.id, kind: .paper, text: $0.title) }
        edges = (database.claimRelations ?? []).filter { $0.projectID == projectID }.map { Edge(source: $0.sourceClaimID, target: $0.targetClaimID, label: $0.relationship.rawValue) }
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        for claim in claims {
            edges += claim.evidence.compactMap { id in evidenceByID[id].map { _ in Edge(source: id, target: claim.id, label: database.relationship(evidenceID: id, claimID: claim.id).rawValue) } }
            let covered = Set(claim.evidence.compactMap { evidenceByID[$0]?.paperID })
            edges += claim.sources.filter { !covered.contains($0) }.map { Edge(source: $0, target: claim.id, label: "source") }
        }
        edges += evidence.map { Edge(source: $0.paperID, target: $0.id, label: "source") }
    }
    public func neighborhood(_ id: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        for edge in edges where edge.source == id || edge.target == id { ids.insert(edge.source); ids.insert(edge.target) }
        // Include the original papers of selected claim's evidence.
        for edge in edges where ids.contains(edge.target) && edge.label == "source" { ids.insert(edge.source) }
        return ids
    }
    public func search(_ text: String) -> [Node] { nodes.filter { $0.text.localizedCaseInsensitiveContains(text) } }
}
public extension ResearchDatabase {
    mutating func addClaimRelation(_ relation: ClaimRelation) throws {
        guard relation.sourceClaimID != relation.targetClaimID,
              claims.contains(where: { $0.id == relation.sourceClaimID && $0.projectID == relation.projectID }),
              claims.contains(where: { $0.id == relation.targetClaimID && $0.projectID == relation.projectID }),
              !(claimRelations ?? []).contains(where: { $0.key == relation.key || $0.id == relation.id }) else {
            throw CoreError.invalid("Choose two different claims in this project and a relationship that does not already exist.")
        }
        claimRelations = (claimRelations ?? []) + [relation]
    }
}
