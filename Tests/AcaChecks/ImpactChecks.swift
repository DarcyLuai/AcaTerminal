import Foundation
import AcaCore
import AcaConnectors
import AcaStorage
import CSQLite

extension Checks {
    static func impactChecks() async throws {
        let old = Date(timeIntervalSince1970: 1_750_000_000)
        var paper = ResearchObject(title: "Known work", doi: "10.1/known")
        paper.sources = [.init(provider: "openalex", externalID: "https://openalex.org/W1")]
        let citing = CitingWork(id: "https://openalex.org/W2", object: ResearchObject(title: "Citing work"))
        var database = ResearchDatabase(); database.objects = [paper]
        func observation(_ count: Int, _ works: [CitingWork], _ date: Date, _ provider: String = "OpenAlex") -> CitationObservation { .init(object: paper, metrics: .init(citationCount: count, updatedAt: date, provider: provider), citingWorks: works, complete: true) }
        try test("Citation baseline is silent, count-independent detection is idempotent") {
            try expect(database.applyCitationObservation(observation(4, [citing], old)).isEmpty, "First baseline is silent")
            let next = CitingWork(id: "https://openalex.org/W3", object: ResearchObject(title: "New citer"))
            try expect(database.applyCitationObservation(observation(4, [citing, next, next], old.addingTimeInterval(86400))).count == 1, "New ID detected despite unchanged total; duplicates collapsed")
            try expect(database.applyCitationObservation(observation(4, [citing, next], old.addingTimeInterval(172800))).isEmpty, "Repeated refresh has no events")
            _ = try database.applyCitationObservation(observation(3, [citing], old.addingTimeInterval(259200)))
            try expect(database.applyCitationObservation(observation(4, [citing, next], old.addingTimeInterval(345600))).isEmpty, "Removed and reappearing citation never alerts twice")
        }
        try test("Incomplete or older observations preserve all previous history") {
            let before = database
            var partial = observation(500, [], Date()); partial.complete = false
            try rejects { _ = try database.applyCitationObservation(partial) }
            try rejects { _ = try database.applyCitationObservation(observation(500, [], old)) }
            try expect(database == before, "Failed observation is atomic")
        }
        try test("Notification claims survive persistence and cannot be claimed twice") {
            try expect(database.claimCitationNotifications().count == 1, "One outbox event")
            var restored = try JSONDecoder().decode(ResearchDatabase.self, from: JSONEncoder().encode(database))
            try expect(restored.claimCitationNotifications().isEmpty, "Relaunch does not duplicate notification")
        }
        try test("Provider baselines and counts remain independent") {
            _ = try database.applyCitationObservation(observation(16, [citing], old.addingTimeInterval(400000), "Semantic Scholar"))
            var identity = ResearcherIdentity(name: "Researcher", orcid: "0000-0002-1825-0097", metrics: .init(citationCount: 18, provider: "OpenAlex"), works: [paper]); database.identity = identity
            let alex = ImpactAnalytics(database: database, provider: "openalex", now: old.addingTimeInterval(400000))
            let semantic = ImpactAnalytics(database: database, provider: "semanticscholar")
            try expect(alex.citationCount == 18 && alex.papers[0].citationCount == 4 && semantic.papers[0].citationCount == 16 && semantic.citationCount == nil, "No mean or mixed provider total")
            identity.metrics = nil; database.identity = identity
        }
        try test("Snapshot time series and citation events survive SQLite restart") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
            do { let repo = try SQLiteRepository(url: url); _ = try repo.load(); try repo.save(database) }
            let restored = try SQLiteRepository(url: url).load()
            try expect(restored.citationSnapshots == database.citationSnapshots && restored.citationEvents == database.citationEvents && restored.citationStates == database.citationStates, "All historical observations retained offline")
        }
        try test("Format 2 migration preserves research, imports identity works and saves backup") {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("research.sqlite")
            var legacy = database; legacy.formatVersion = 2; legacy.citationEvents = nil; legacy.citationStates = nil; legacy.impactRefresh = nil
            let note = ResearchNote(paperID: paper.id, text: "Private note"); legacy.notes = [note]
            do { let repo = try SQLiteRepository(url: url); _ = try repo.load(); try repo.save(database) }
            var sqlite: OpaquePointer?; try expect(sqlite3_open(url.path, &sqlite) == SQLITE_OK, "Fixture SQLite open")
            let payload = try JSONEncoder().encode(legacy)
            var statement: OpaquePointer?; sqlite3_prepare_v2(sqlite, "UPDATE workspace SET payload=? WHERE id=1", -1, &statement, nil)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(payload.count), transient) }
            try expect(sqlite3_step(statement) == SQLITE_DONE, "Legacy fixture stored"); sqlite3_finalize(statement); sqlite3_close(sqlite)
            let migrated = try SQLiteRepository(url: url).load()
            try expect(migrated.formatVersion == 5 && migrated.notes == [note] && migrated.citationSnapshots == legacy.citationSnapshots, "Existing content and snapshots retained")
            try expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix("migration-format-2-") }, "Raw pre-migration backup exists")
        }
        try test("Identity refresh retains stable IDs, local titles and research links") {
            var db = ResearchDatabase(); db.objects = [paper]
            var incoming = paper; incoming.id = UUID(); incoming.title = "Provider renamed it"
            db.adoptIdentity(.init(name: "Person", orcid: "0000-0002-1825-0097", works: [incoming]))
            db.adoptIdentity(.init(name: "Person", orcid: "0000-0002-1825-0097", works: [incoming]))
            try expect(db.objects.count == 1 && db.identity?.works.first?.id == paper.id && db.objects[0].title == "Known work", "No duplicate owned works")
        }
        try test("Analytics preserves annual scope and computes observed growth rates") {
            var db = ResearchDatabase(); db.objects = [paper]
            db.identity = .init(name: "Person", orcid: "", metrics: .init(citationCount: 900, citationsByYear: [.init(year: 2025, count: 5), .init(year: 2026, count: 8)], provider: "OpenAlex"), works: [paper])
            db.citationSnapshots = [.init(objectID: paper.id, metrics: .init(citationCount: 10, updatedAt: old, provider: "OpenAlex")), .init(objectID: paper.id, metrics: .init(citationCount: 14, updatedAt: old.addingTimeInterval(2 * 86400), provider: "OpenAlex"))]
            let data = ImpactAnalytics(database: db, provider: "openalex")
            try expect(data.years.last?.cumulative == 13 && data.citationCount == 900, "Available-years sum never pretends to be lifetime total")
            try expect(data.papers[0].growthPerDay == 2, "Growth is per day, not unequal interval raw deltas")
        }
        try test("1,000-work analytics remains bounded and computes offline") {
            var db = ResearchDatabase(); var works: [ResearchObject] = []
            for index in 0..<1000 { var work = ResearchObject(title: "Work \(index)", year: 2020 + index % 7); work.sources = [.init(provider: "openalex", externalID: "W\(index)")]; works.append(work); for day in 0..<12 { db.citationSnapshots.append(.init(objectID: work.id, metrics: .init(citationCount: index + day, updatedAt: old.addingTimeInterval(Double(day) * 86400), provider: "OpenAlex"))) } }
            db.objects = works; db.identity = .init(name: "Person", orcid: "", works: works)
            let start = Date(); let analytics = ImpactAnalytics(database: db, provider: "OpenAlex")
            try expect(analytics.papers.count == 1000 && analytics.observations.count == 12000 && Date().timeIntervalSince(start) < 3, "1,000 works / 12,000 snapshots under 3 seconds")
            print("METRIC Analytics 1000 works: \(Int(Date().timeIntervalSince(start)*1000)) ms")
        }
        try test("Full-text priorities distinguish published, accepted and preprint") {
            let url = URL(string: "https://example.org/file.pdf")!
            let locations: [FullTextLocation] = [.init(provider: "arXiv", url: url, accessType: .openAccess, version: .preprint, isDirectPDF: true), .init(provider: "Repository", url: url, accessType: .openAccess, version: .accepted, isDirectPDF: true), .init(provider: "Publisher", url: url, accessType: .openAccess, version: .published, isDirectPDF: true)]
            try expect(locations.sorted { $0.priority < $1.priority }.map(\.version) == [.published,.accepted,.preprint], "Version priority")
            try expect(PaperVersion(apiValue: nil) == .unknown && PaperVersion(apiValue: "submittedVersion") == .preprint, "Unknown versions never become Version of Record")
            try expect(!FullTextDownload.safeURL(URL(string: "http://publisher.example/a.pdf")!), "No insecure download")
        }
        let oa = FixtureHTTP { _ in Data(#"{"id":"https://openalex.org/W1","cited_by_count":2,"locations":[{"is_oa":false,"pdf_url":"https://publisher.example/paywalled.pdf","landing_page_url":"https://jstor.org/stable/1","version":"publishedVersion"},{"is_oa":true,"pdf_url":"https://repository.example/accepted.pdf","version":"acceptedVersion","source":{"type":"repository"}}]}"#.utf8) }
        let resolved = try await OpenAlexProvider(transport: oa).resolve(paper)
        try test("OpenAlex paywalled PDF stays a landing link; accepted OA stays accepted") {
            try expect(resolved[0].isDirectPDF == false && resolved[0].url.host == "jstor.org", "Never download closed PDF URL")
            try expect(resolved[1].version == .accepted && resolved[1].isDirectPDF, "OA author manuscript remains labeled")
        }
        let unpaywall = FixtureHTTP { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            try expect(parts.host == "api.unpaywall.org" && parts.queryItems?.first?.name == "email", "Unpaywall official API and contact email")
            return Data(#"{"oa_locations":[{"url_for_pdf":"https://example.org/a.pdf","version":"publishedVersion","host_type":"publisher"}]}"#.utf8)
        }
        let unpaywallLocations = try await UnpaywallFullTextProvider(email: "fixture@example.org", transport: unpaywall).resolve(paper)
        try test("Unpaywall parses version and direct PDF metadata") { try expect(unpaywallLocations.first?.version == .published, "Published OA version") }
        var preprint = ResearchObject(title: "Preprint"); preprint.arxivID = "2205.01833v2"
        let arxiv = try await ArxivFullTextProvider().resolve(preprint)
        try test("arXiv explicit revision is retained and classified as preprint") { try expect(arxiv.first?.url.path == "/pdf/2205.01833v2" && arxiv.first?.version == .preprint, "No pretend published version") }
        let offline = FixtureHTTP { _ in throw CoreError.invalid("Offline") }
        let offlineResolution = await FullTextResolver().resolve(paper, providers: [OpenAlexProvider(transport: offline), PublisherFullTextProvider()])
        try test("Offline resolution preserves fallback and reports failed provider") { try expect(!offlineResolution.locations.isEmpty && offlineResolution.failures.count == 1, "One failing provider doesn't erase fallback") }
        let paging = FixtureHTTP { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            if parts.path == "/works/W1" { return Data(#"{"id":"https://openalex.org/W1","cited_by_count":17}"#.utf8) }
            let cursor = parts.queryItems?.first { $0.name == "cursor" }?.value
            if cursor == "*" { return Data(#"{"meta":{"count":2,"next_cursor":"next"},"results":[{"id":"https://openalex.org/W2","title":"Citer 1","cited_by_count":0,"publication_date":"2026-01-02"}]}"#.utf8) }
            return Data(#"{"meta":{"count":2,"next_cursor":null},"results":[{"id":"https://openalex.org/W3","title":"Citer 2","cited_by_count":0}]}"#.utf8)
        }
        let state = try await OpenAlexProvider(transport: paging).citationState(for: paper)
        try test("Citation monitor retrieves every cursor page despite count lag") { try expect(state.complete && state.citingWorks.count == 2 && state.metrics.citationCount == 17 && state.citingWorks[0].publicationDate != nil, "Citing IDs, not metric delta, determine new citations") }
        let unavailable = FixtureHTTP { _ in throw CoreError.invalid("Temporary outage") }
        do { _ = try await OpenAlexProvider(transport: unavailable).citationState(for: paper); throw CheckFailure(description: "Expected API outage") } catch is CheckFailure { throw CheckFailure(description: "Expected API outage") } catch {}
        try test("Stale refresh scheduling is daily and failures do not busy-loop") {
            var state = ImpactRefreshState(); state.lastAttempt = Date()
            try expect(!state.isStale() && state.isStale(at: Date().addingTimeInterval(86401)), "Attempt backoff, not high-frequency polling")
        }
    }
}
