import Foundation
import AcaCore
import AcaStorage
import AcaConnectors
import CSQLite

extension Checks {
    static func advancedChecks() async throws {
        var db = ResearchDatabase()
        let project = ResearchProject(title: "Private project", question: "SECRET-question political evaluation risk")
        var paper = ResearchObject(title: "Locally edited SECRET-title", doi: "10.1234/public"); paper.projects = [project.id]
        paper.sources = [.init(provider: "openalex", externalID: "https://openalex.org/W1")]
        let a = Claim(projectID: project.id, text: "SECRET-claim political evaluation influences risk")
        let b = Claim(projectID: project.id, text: "Institutional constraints qualify risk")
        db.projects = [project]; db.objects = [paper]; db.claims = [a, b]
        var evidence = Evidence(paperID: paper.id, page: "12", quote: "SECRET-evidence", note: "PRIVATE-note")
        evidence.documentID = "original"; evidence.locations = [.init(page: 11, x: 0.1, y: 0.5, width: 0.7, height: 0.1)]
        try db.saveEvidence(evidence, projectID: project.id, claimID: a.id)
        try test("Claim relations are directional, scoped, unique and non-self") {
            let relation = ClaimRelation(projectID: project.id, sourceClaimID: a.id, targetClaimID: b.id, relationship: .qualifies)
            try db.addClaimRelation(relation); try db.validate()
            try rejects { try db.addClaimRelation(relation) }
            try rejects { try db.addClaimRelation(.init(projectID: project.id, sourceClaimID: a.id, targetClaimID: a.id, relationship: .supports)) }
            try rejects { try db.addClaimRelation(.init(projectID: UUID(), sourceClaimID: a.id, targetClaimID: b.id, relationship: .supports)) }
            try expect(db.claimRelations?.count == 1, "Invalid relations do not mutate database")
        }
        try test("Graph search and focus preserve claim → evidence → paper paths") {
            let graph = ClaimGraph(database: db, projectID: project.id)
            try expect(graph.nodes.count == 4 && graph.edges.count == 3, "Typed graph nodes and links")
            try expect(graph.neighborhood(a.id).contains(paper.id), "Focus includes original source")
            try expect(graph.search("political").map(\.id) == [a.id], "Local graph search")
            if case .evidence(let items) = db.query(.evidence(a.id)) { try expect(items.first?.locations == evidence.locations, "Query preserves PDF coordinates") } else { throw CheckFailure(description: "Wrong query result") }
        }
        let profile = ProjectResearchProfile(database: db, projectID: project.id)
        try test("Discovery request exposes only validated public IDs, bounded to five seeds") {
            try expect(profile.request.seedIDs == ["W1"], "Prefer canonical public ID")
            try expect(profile.localTerms.contains("secret"), "Private data remains available for LOCAL ranking")
            try expect(DiscoveryRequest(seedIDs: ["PRIVATE claim", "file:///tmp/paper.pdf", "https://evil.com/W1", "10.1234/valid"]).seedIDs == ["https://doi.org/10.1234/valid"], "No arbitrary URLs or project text")
            try expect(DiscoveryRequest(seedIDs: (1...10).map { "W\($0)" }).seedIDs.count == 5, "Bounded seed budget")
        }
        let seed = DiscoveryWork(id: "W1", object: paper, references: ["W90", "W91"], authorIDs: ["A1"], topicIDs: ["T1"])
        var candidate = ResearchObject(title: "Political evaluation challenges risk models", doi: "10.1234/new")
        candidate.abstract = "A measurement method challenges political evaluation."
        let work = DiscoveryWork(id: "W2", object: candidate, references: ["W1", "W90"], authorIDs: ["A1"], topicIDs: ["T1"], publicationDate: Date().addingTimeInterval(-86400), citationCount: 80, providerRelated: true)
        let baseline = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: []))
        let cache = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: [work, work], checkedAt: Date().addingTimeInterval(1)))
        try test("Explainable ranking distinguishes factual citations from potential keyword challenges") {
            let rec = cache.recommendations[0]
            try expect(cache.recommendations.count == 1 && rec.categories.contains(.potentialChallenges), "Deduplicate and flag potential only")
            try expect(rec.reasons.contains { $0.kind == .citesProject && $0.count == 1 }, "Citation provenance")
            try expect(rec.reasons.contains { $0.kind == .sharedReferences && $0.count == 1 }, "Shared-reference count")
            try expect(rec.reasons.contains { $0.claimID == a.id }, "Explain which local claim matched")
            try expect(rec.categories.contains(.methods) && rec.categories.contains(.recent), "Methods and recency heuristics")
        }
        try test("First discovery is silent; later diff is work-based and idempotent") {
            db.recordDiscovery(baseline); try expect((db.literatureChanges ?? []).isEmpty, "Silent baseline")
            db.recordDiscovery(cache); db.recordDiscovery(cache)
            try expect(db.literatureChanges?.count == 1 && db.unreviewedChanges(projectID: project.id).count == 1, "One work, not six noisy events")
            let change = db.literatureChanges![0].changes[0]
            try expect(change.kinds.contains(.newCitationToProjectPaper) && change.kinds.contains(.newWorkByTrackedAuthor) && change.kinds.contains(.newWorkInTrackedTopic), "Factual categories")
            try expect(change.kinds.contains(.potentialClaimChallenge), "Potential, not a conclusion")
        }
        try test("Cumulative snapshots prevent disappearing/reappearing works from re-alerting") {
            var absent = baseline; absent.checkedAt = Date().addingTimeInterval(2)
            db.recordDiscovery(absent)
            var returning = cache; returning.checkedAt = Date().addingTimeInterval(3)
            db.recordDiscovery(returning)
            try expect(db.literatureChanges?.count == 1 && db.literatureSnapshots?.last?.knownWorkIDs == ["W2"], "Never overwrite historical known IDs")
        }
        try test("Changing public seed scope establishes a new silent baseline") {
            var altered = cache; altered.scope = "W99"; altered.recommendations[0].work.id = "W3"; altered.checkedAt = Date().addingTimeInterval(4)
            db.recordDiscovery(altered)
            try expect(db.literatureChanges?.count == 1, "Scope expansion is not a publication alert")
        }
        try test("Feedback suppresses future irrelevant/already-known events and can be changed") {
            db.recordFeedback(.init(projectID: project.id, provider: "openalex", workID: "W2", judgment: .notRelevant))
            let changes = LiteratureChangeSet(cache: cache, previous: LiteratureSnapshot(cache: baseline, previous: nil), feedback: db.discoveryFeedback!)
            try expect(changes.changes.isEmpty, "Dismissed recommendation does not notify")
            db.recordFeedback(.init(projectID: project.id, provider: "openalex", workID: "W2", judgment: .relevant))
            try expect(db.discoveryFeedback?.count == 1, "Feedback upsert")
            let ranked = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: [work]), feedback: db.discoveryFeedback!)
            try expect(ranked.recommendations[0].score > cache.recommendations[0].score, "Relevant feedback participates in ranking")
        }
        try test("Advanced state persists offline with source anchors and graph links") {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".sqlite")
            let repo = try SQLiteRepository(url: url); _ = try repo.load(); try repo.save(db)
            let reopened = try SQLiteRepository(url: url).load()
            try expect(reopened == db && reopened.evidence[0].locations == evidence.locations, "Offline round trip is lossless")
            if case .changes(let sets) = reopened.query(.changes(project.id, since: Date().addingTimeInterval(-10))) { try expect(sets.count == 1, "Unified local change query") }
        }
        try test("Format 3 migration backs up payload and preserves all existing objects") {
            var old = db; old.formatVersion = 3; old.claimRelations = nil; old.discoveryCaches = nil; old.discoveryFeedback = nil; old.literatureChanges = nil; old.literatureSnapshots = nil
            let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            let url = folder.appendingPathComponent("research.sqlite")
            _ = try SQLiteRepository(url: url)
            var raw: OpaquePointer?; sqlite3_open(url.path, &raw); defer { sqlite3_close(raw) }
            let data = try JSONEncoder().encode(old), hex = data.map { String(format: "%02x", $0) }.joined()
            try expect(sqlite3_exec(raw, "INSERT INTO workspace VALUES(1,X'\(hex)',1)", nil, nil, nil) == SQLITE_OK, "Seed legacy payload")
            let loaded = try SQLiteRepository(url: url).load()
            try expect(loaded.formatVersion == 5 && loaded.claimRelations == [] && loaded.discoveryCaches == [], "Optional fields migrate")
            try expect(loaded.objects == old.objects && loaded.claims == old.claims && loaded.evidence == old.evidence && loaded.citationSnapshots == old.citationSnapshots, "Existing research untouched")
            try expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("migration-format-3-1.json").path), "Raw format3 backup")
        }
        let http = FixtureHTTP { request in
            let url = request.url!.absoluteString
            try expect(!url.contains("SECRET") && request.httpBody == nil && request.url?.host == "api.openalex.org", "Only public IDs go over network")
            let json = #"{"id":"https://openalex.org/W1","display_name":"Public seed","authorships":[{"author":{"id":"https://openalex.org/A1","display_name":"Author"}}],"referenced_works":["https://openalex.org/W90"],"related_works":["https://openalex.org/W2"],"primary_topic":{"id":"https://openalex.org/T1"}}"#
            return Data((request.url!.path == "/works/W1" ? json : "{\"results\":[" + json.replacingOccurrences(of: "W1\"", with: "W2\"") + "]}").utf8)
        }
        let batch = try await OpenAlexDiscoveryProvider(transport: http).discover(profile.request)
        let requests = await http.requests
        try test("OpenAlex adapter uses official ID filters and bounded public-only requests") {
            try expect(batch.seeds.count == 1 && requests.count == 5, "One seed plus four bounded categories")
            let filters = requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filter" }?.value }
            try expect(filters.contains("cites:W1") && filters.contains("primary_topic.id:T1") && filters.contains("authorships.author.id:A1"), "Exact filters")
        }
        let failing = FixtureHTTP { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await OpenAlexDiscoveryProvider(transport: failing).discover(profile.request); throw CheckFailure(description: "Expected offline failure") } catch is URLError { }
        try test("Offline provider failure leaves cache and baseline intact") { try expect(db.discoveryCaches?.count == 1 && db.literatureChanges?.count == 1, "No partial replacement on failure") }
        try test("Known works gaining a project citation generate one new citation change") {
            var withoutCitation = work; withoutCitation.references = ["W90"]
            let before = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: [withoutCitation]))
            let previous = LiteratureSnapshot(cache: before, previous: nil)
            let delta = LiteratureChangeSet(cache: cache, previous: previous)
            try expect(delta.changes.count == 1 && delta.changes[0].kinds == [.newCitationToProjectPaper], "Already-known work changes citation state")
            let after = LiteratureSnapshot(cache: cache, previous: previous)
            try expect(LiteratureChangeSet(cache: cache, previous: after).changes.isEmpty, "No repeat citation alert")
        }
        try test("Aggregated literature notification claims are durable and at-most-once") {
            let pending = db.claimLiteratureNotifications(projectID: project.id)
            try expect(pending.count == 1 && db.claimLiteratureNotifications(projectID: project.id).isEmpty, "Claim once per change set")
            var restored = try JSONDecoder().decode(ResearchDatabase.self, from: JSONEncoder().encode(db))
            try expect(restored.claimLiteratureNotifications(projectID: project.id).isEmpty, "Relaunch cannot duplicate notification")
        }
        try test("1000-work local ranking and large graph remain bounded") {
            var many = db; many.claims = (0..<1000).map { Claim(projectID: project.id, text: "Claim \($0) evaluation risk") }; many.claimRelations = []
            let start = Date(); let graph = ClaimGraph(database: many, projectID: project.id)
            let works = (0..<1000).map { n -> DiscoveryWork in var item = work; item.id = "W\(n+100)"; return item }
            let ranked = DiscoveryCache(profile: profile, batch: .init(provider: "openalex", seeds: [seed], works: works))
            let elapsed = Date().timeIntervalSince(start)
            print("METRIC graph 1000 claims + ranking 1000 works: \(Int(elapsed * 1000)) ms")
            try expect(graph.nodes.count >= 1000 && ranked.recommendations.count == 1000 && elapsed < 5, "Bounded work; production performs this off-main")
        }
    }
}
