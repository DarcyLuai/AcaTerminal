import Foundation
import AcaCore
import AcaStorage
import AcaConnectors
import CSQLite

extension Checks {
    static func researchMarkChecks() throws {
        let documentID = "document-fixture", externalID = "CLAIM-003"
        func exchange(_ text: String = "Persistence clusters risky actions temporally.", id: String = "CLAIM-003", type: ResearchMarkType = .claim) -> ResearchMarkExchange {
            .init(sourceApp: "AcaTex", projectID: documentID, sourceDocument: documentID, marks: [.init(id: id, type: type, text: text, sourceApp: "AcaTex", sourceDocument: documentID, projectID: documentID, anchorNodeID: "paragraph-1")])
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AcaResearchChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        var db = ResearchDatabase(); let project = ResearchProject(title: "Mark workflow"); db.projects = [project]
        let connection = AcaTexConnection(projectID: project.id, documentID: documentID, fileURL: dir.appendingPathComponent("project.texflow")); db.acaTexConnections = [connection]
        try test("AcaTex native paragraph anchors preserve stable IDs and all argument types") {
            let types = ["researchQuestion", "claim", "hypothesis", "finding"]
            let marks = types.enumerated().map { ["id": "MARK-\($0.offset)", "type": $0.element, "anchorNodeId": "p\($0.offset)"] }
            let paragraphs: [[String: Any]] = types.enumerated().map { ["type":"paragraph", "attrs":["nodeId":"p\($0.offset)"], "content":[["type":"text", "text":"Same title"]]] }
            let native: [String: Any] = ["version":13,"documentId":documentID,"content":["type":"doc","attrs":["documentId":documentID,"researchObjects":marks],"content":paragraphs]]
            let decoded = try AcaTexProjectReader().decode(JSONSerialization.data(withJSONObject: native))
            try expect(decoded.marks.map(\.type) == ResearchMarkType.arguments && decoded.marks[1].id == "MARK-1", "Native fields")
            var local = db; try local.ingestMarks(decoded, connectionID: connection.id); try expect(local.claims.count == 4, "Identical text never merges distinct marks")
        }
        try db.ingestMarks(exchange(), connectionID: connection.id); let claimID = db.claims[0].id
        try test("Repeated sync updates one logical claim and never uses title matching") {
            try db.ingestMarks(exchange(), connectionID: connection.id); try db.ingestMarks(exchange("Updated in AcaTex"), connectionID: connection.id)
            try expect(db.claims.count == 1 && db.claims[0].id == claimID && db.claims[0].text == "Updated in AcaTex", "Update in place")
            try expect(db.binding(for: claimID)?.externalID == externalID, "External ID preserved verbatim")
        }
        try test("UUID marks retain their native identity") {
            var local = db; let id = UUID(); try local.ingestMarks(exchange(id: id.uuidString), connectionID: connection.id)
            try expect(local.claims.contains { $0.id == id }, "Native UUID retained")
        }
        try test("Both-side edits retain versions and reject export until conflict resolution") {
            db.claims[0].text = "Local unpublished claim"
            try db.ingestMarks(exchange("Remote unpublished claim"), connectionID: connection.id)
            try expect(db.syncStatus(for: claimID) == .conflict && db.claims[0].text == "Local unpublished claim", "No silent overwrite")
            try db.ingestMarks(exchange("Remote unpublished claim"), connectionID: connection.id)
            try expect(db.binding(for: claimID)?.conflicts.count == 1, "Repeated refresh does not duplicate conflict")
            try rejects { _ = try db.exportMarks(connectionID: connection.id, claimIDs: [claimID]) }
            try db.resolveMarkConflict(claimID, useRemote: false)
            try db.ingestMarks(exchange("Remote unpublished claim"), connectionID: connection.id)
            try expect(db.syncStatus(for: claimID) == .changedInAcaTerminal && db.claims[0].text == "Local unpublished claim", "Keep local persists through refresh")
            try expect(db.binding(for: claimID)?.conflicts[0].resolvedAt != nil, "Conflict archive retained")
        }
        try test("Remote conflict resolution updates original identity") {
            var local = db; try local.ingestMarks(exchange("Another remote edit"), connectionID: connection.id); try local.resolveMarkConflict(claimID, useRemote: true)
            try expect(local.claims[0].id == claimID && local.claims[0].text == "Another remote edit" && local.syncStatus(for: claimID) == .synced, "Explicit remote choice")
        }
        let paper = ResearchObject(title: "Source Paper"); db.objects = [paper]
        var evidence = Evidence(paperID: paper.id, page: "17", quote: "Exact source selection", relationship: .supports)
        evidence.documentID = "pdf-fingerprint"; evidence.locations = [.init(page: 16, x: 12, y: 45, width: 160, height: 14)]
        try db.saveEvidence(evidence, projectID: project.id, claimID: claimID)
        let hypothesis = Claim(projectID: project.id, text: "An alternative hypothesis"); db.claims.append(hypothesis)
        try test("Evidence relationships belong to each link, including qualifies and challenges") {
            try db.attachEvidence(evidence.id, to: hypothesis.id, relationship: .qualifies)
            try db.attachEvidence(evidence.id, to: hypothesis.id)
            try expect(db.relationship(evidenceID: evidence.id, claimID: claimID) == .supports && db.relationship(evidenceID: evidence.id, claimID: hypothesis.id) == .qualifies, "Independent links; repeated drag preserves relation")
            try db.attachEvidence(evidence.id, to: hypothesis.id, relationship: .challenges)
            try expect(db.evidenceRelations?.count == 2 && db.relationship(evidenceID: evidence.id, claimID: hypothesis.id) == .challenges, "Update without duplicate")
        }
        try test("Versioned export preserves evidence anchor and relation across multiple marks") {
            let exported = try db.exportMarks(connectionID: connection.id, claimIDs: [claimID, hypothesis.id])
            let restored = try ResearchMarkCodec.decode(ResearchMarkCodec.encode(exported))
            let item = restored.marks.first { $0.type == .evidence }!
            try expect(item.links.count == 2 && item.evidence?.anchor.locations == evidence.locations, "One evidence, two relationships, exact selection")
            try expect(restored.marks.first { $0.id == externalID }?.text == "Local unpublished claim", "Original ID sent")
            try expect(db.syncStatus(for: hypothesis.id) == .changedInAcaTerminal, "New local mark pending review")
        }
        try test("Save/reopen retains imported claim, binding, conflicts, evidence and relationships") {
            let path = dir.appendingPathComponent("workspace.sqlite"); let repo = try SQLiteRepository(url: path); _ = try repo.load(); try repo.save(db)
            let reopened = try SQLiteRepository(url: path).load()
            try expect(reopened.claims[0].id == claimID && reopened.evidence[0].locations == evidence.locations, "Restart identity/anchor")
            try expect(reopened.relationship(evidenceID: evidence.id, claimID: hypothesis.id) == .challenges && reopened.binding(for: claimID)?.conflicts.count == 1, "Restart link/conflict")
        }
        try test("Build 8 payload 4 migrates additively with byte-for-byte backup") {
            var legacy = db; legacy.formatVersion = 4; legacy.acaTexConnections = nil; legacy.markBindings = nil; legacy.evidenceRelations = nil
            let bytes = try JSONEncoder().encode(legacy), path = dir.appendingPathComponent("build8.sqlite")
            var handle: OpaquePointer?; sqlite3_open(path.path, &handle); defer { sqlite3_close(handle) }
            sqlite3_exec(handle, "CREATE TABLE workspace(id INTEGER PRIMARY KEY,payload BLOB,revision INTEGER); PRAGMA user_version=1", nil,nil,nil)
            var statement: OpaquePointer?; sqlite3_prepare_v2(handle, "INSERT INTO workspace VALUES(1,?,8)", -1,&statement,nil)
            _ = bytes.withUnsafeBytes { sqlite3_bind_blob(statement,1,$0.baseAddress,Int32(bytes.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }; sqlite3_step(statement); sqlite3_finalize(statement)
            let migrated = try SQLiteRepository(url: path).load()
            try expect(migrated.formatVersion == 5 && migrated.claims.map(\.id) == legacy.claims.map(\.id) && migrated.evidence == legacy.evidence, "All old research retained")
            try expect(try Data(contentsOf: dir.appendingPathComponent("migration-format-4-8.json")) == bytes, "Original payload backup")
            try expect(migrated.evidenceRelations?.count == 2, "Legacy links backfilled")
        }
        try test("Missing/changed document sources cannot delete or cross-link local research") {
            var local = db; var empty = exchange(); empty.marks = []; try local.ingestMarks(empty, connectionID: connection.id)
            try expect(local.claims.count == db.claims.count && local.syncStatus(for: claimID) == .sourceMissing, "Missing source retained")
            var other = exchange(); other.sourceDocument = "different"; try rejects { try local.ingestMarks(other, connectionID: connection.id) }
            var duplicate = exchange(); duplicate.marks.append(duplicate.marks[0]); try rejects { try duplicate.validate() }
            try rejects { _ = try AcaTexProjectReader().decode(Data("{partial".utf8)) }
        }
        try test("Imported private marks stay local; per-mark discovery hints remain potential") {
            var local = db; local.claims[0].markType = .hypothesis; local.claims[0].text = "Persistence temporal clustering secret hypothesis"
            local.objects[0].doi = "10.1234/public"; local.objects[0].projects = [project.id]
            let profile = ProjectResearchProfile(database: local, projectID: project.id)
            try expect(profile.request.seedIDs == ["https://doi.org/10.1234/public"], "Only public ID leaves local profile")
            let work = DiscoveryWork(id: "W200", object: ResearchObject(title: "Persistence temporal clustering evidence"))
            let cache = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [], works: [work]))
            try expect(cache.recommendations.first?.markMatches?.contains(where: { $0.markID == claimID && $0.type == .hypothesis && $0.suggestion.hasPrefix("Potential") }) == true, "Typed hypothesis hint with qualified label")
        }
        try test("One thousand imported stable marks merge without duplicates") {
            var local = db; var many = exchange(); many.marks = (0..<1000).map { index in ResearchMark(id: "claim-\(index)", type: .claim, text: "Claim \(index)", sourceApp: "AcaTex", sourceDocument: documentID, projectID: documentID) }
            let start = Date(); try local.ingestMarks(many, connectionID: connection.id); try local.ingestMarks(many, connectionID: connection.id)
            try expect(local.claims.count == db.claims.count + 1000, "Stable duplicate prevention at 1000 marks")
            print("METRIC 1000 marks initial merge + repeat: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        try test("Deep links are scoped by IDs and reject arbitrary local file access") {
            let url = ResearchRoute.evidence(paperID: paper.id, evidenceID: evidence.id).url
            try expect(ResearchRoute(url: url) != nil && ResearchRoute(url: URL(string: "file:///tmp/private")!) == nil, "Strict Terminal route")
            try expect(ResearchRoute(url: URL(string: url.absoluteString + "?path=/tmp")!) == nil, "No arbitrary route parameters")
            let aca = URLComponents(url: ResearchRoute.acaTex(documentID: "doc & /", markID: externalID), resolvingAgainstBaseURL: false)!
            try expect(aca.queryItems?.first { $0.name == "document" }?.value == "doc & /", "AcaTex IDs safely encoded")
        }
    }
}
