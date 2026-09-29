import Foundation
import AcaCore
import AcaStorage
import AcaConnectors
import CSQLite

struct CheckFailure: Error, CustomStringConvertible { var description: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws { if try !condition() { throw CheckFailure(description: message) } }
func rejects(_ action: () throws -> Void) throws { do { try action() } catch { return }; throw CheckFailure(description: "Expected failure, but operation succeeded") }
final class MemoryCredentials: CredentialStore {
    var values: [String: String] = [:]
    func read(_ key: String) throws -> String? { values[key] }
    func write(_ value: String, for key: String) throws { values[key] = value }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
actor FixtureHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    let response: (URLRequest) throws -> Data
    init(_ response: @escaping (URLRequest) throws -> Data) { self.response = response }
    func data(for request: URLRequest) async throws -> Data { requests.append(request); return try response(request) }
}
@main struct Checks {
    static var count = 0
    static func test(_ name: String, _ body: () throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
    static func main() async {
        do {
            try researchMarkChecks()
            try await advancedChecks()
            try await impactChecks()
            try test("Submission links identify official hosts and reject credential URLs") {
                try expect(SubmissionLink.parse("https://mc.manuscriptcentral.com/isq").platform == "ScholarOne", "ScholarOne host")
                try expect(SubmissionLink.parse("https://www.editorialmanager.com/example/").platform == "Editorial Manager", "Editorial Manager host")
                try expect(SubmissionLink.parse("https://openreview.net.evil.example/forum?id=abc").openReviewID == nil, "Host suffix spoof is not OpenReview")
                try rejects { _ = try SubmissionLink.parse("https://user:password@example.org") }
                try rejects { _ = try SubmissionLink.parse("file:///etc/passwd") }
                try rejects { _ = try SubmissionLink.parse("https://127.0.0.1/status") }
            }
            let submissionHTTP = FixtureHTTP { request in
                try expect(request.url?.host == "api2.openreview.net", "Only official OpenReview API")
                if request.url!.query!.contains("forum=") {
                    return Data(#"{"notes":[{"readers":["everyone"],"invitations":["Venue/Paper1/-/Official_Comment"],"content":{"decision":{"value":"Reject"}},"tmdate":999},{"readers":["everyone"],"invitations":["Venue/Paper1/-/Decision"],"content":{"decision":{"value":"Accept (Poster)"}},"tmdate":100}]}"#.utf8)
                }
                return Data(#"{"notes":[{"id":"paper1","readers":["everyone"],"content":{"title":{"value":"A research question"},"venue":{"value":"Test Conference"}}}]}"#.utf8)
            }
            let resolvedSubmission = try await SubmissionLinkProvider(transport: submissionHTTP).lookup("https://openreview.net/forum?id=paper1")
            try test("OpenReview retrieves public metadata and official decision without inventing dates") {
                try expect(resolvedSubmission.title == "A research question" && resolvedSubmission.journal == "Test Conference", "Public bibliographic details")
                try expect(resolvedSubmission.status == .accepted && resolvedSubmission.statusRaw == "Accept (Poster)", "Official decision, not an arbitrary comment")
                try expect(resolvedSubmission.submittedAt == nil, "No fabricated submission date")
            }
            let noNetwork = FixtureHTTP { _ in throw CheckFailure(description: "Private journal portal must not be scraped") }
            let privateSubmission = try await SubmissionLinkProvider(transport: noNetwork).lookup("https://www.editorialmanager.com/example/")
            try test("Private submission portals remain unknown until authenticated or supplemented") {
                try expect(privateSubmission.status == nil && privateSubmission.statusRaw == nil, "Platform recognition never guesses status")
                var item = Submission(title: "Untitled", journal: "example", status: .unknown); item.submissionDateUnknown = true
                let decoded = try JSONDecoder().decode(Submission.self, from: JSONEncoder().encode(item))
                try expect(decoded.submissionDateUnknown == true, "Unknown date survives persistence")
            }
            try test("Persistent IDs, fallback review and conflicting DOI protection") {
                var paper = ResearchObject(title: "A Theory of War", authors: [.init("Ada Smith")], year: 2025, doi: "10.1234/abc")
                var incoming = paper; incoming.id = UUID(); incoming.doi = "https://doi.org/10.1234/ABC"
                let resolver = ResearchObjectResolver()
                try expect(resolver.resolve(incoming, in: [paper]) == .match(paper.id), "DOI URL normalization")
                incoming.doi = nil; try expect(resolver.resolve(incoming, in: [paper]) == .possible([paper.id]), "Title matches require review")
                incoming.doi = "10.1234/other"; incoming.arxivID = "2401.00001v2"; paper.arxivID = "https://arxiv.org/abs/2401.00001"
                try expect(resolver.resolve(incoming, in: [paper]) == .possible([paper.id]), "Conflicting DOI must not merge through arXiv")
                incoming.doi = nil; try expect(resolver.resolve(incoming, in: [paper]) == .match(paper.id), "arXiv version canonicalization")
                incoming.arxivID = nil; incoming.isbn = "978-1-234-56789-0"; paper.isbn = "9781234567890"
                try expect(resolver.resolve(incoming, in: [paper]) == .match(paper.id), "ISBN normalization")
                try expect(ResearchObjectResolver.doi("doi:") == nil, "Empty DOI is not an identity")
            }
            try test("Import idempotence, note remapping, metadata and project preservation") {
                var db = ResearchDatabase(); let p = ResearchProject(title: "Project"); db.projects = [p]
                var existing = ResearchObject(title: "Local title", doi: "10.1/same"); existing.projects = [p.id]; db.objects = [existing]
                var item = ResearchObject(title: "Provider title", doi: "10.1/same"); item.sources = [.init(provider: "zotero", externalID: "users/1:ABC")]
                let note = ResearchNote(paperID: item.id, text: "Imported note", sourceID: "zotero:NOTE")
                let batch = LibraryImport(objects: [item], notes: [note]); try db.apply(batch); try db.apply(batch)
                try expect(db.objects.count == 1 && db.notes.count == 1, "Repeat import creates no duplicates")
                try expect(db.notes[0].paperID == existing.id && db.objects[0].projects == [p.id] && db.objects[0].title == "Local title", "Stable research links")
                var other = ResearchObject(title: "Local title", authors: [.init("Ada")], year: 2025); db.objects[0].authors = other.authors; db.objects[0].year = other.year
                other.doi = "10.2/conflict"; let before = db
                try rejects { try db.apply(.init(objects: [other])) }; try expect(db == before, "Ambiguous import is atomic")
                try db.apply(.init(objects: [other]), decisions: [other.id: .separate]); try expect(db.objects.count == 2, "Explicit keep separate")
            }
            try test("Evidence attaches to claim, source and project") {
                var db = ResearchDatabase(); let p = ResearchProject(title: "P"); let paper = ResearchObject(title: "Paper"); let claim = Claim(projectID: p.id, text: "Claim")
                db.projects = [p]; db.objects = [paper]; db.claims = [claim]
                let evidence = Evidence(paperID: paper.id, page: "12", quote: "Observation", relationship: .contradicts)
                try db.addEvidence(evidence, to: claim.id); try db.validate()
                try expect(db.claims[0].evidence == [evidence.id] && db.claims[0].sources == [paper.id] && db.objects[0].projects == [p.id], "Evidence relations")
                try rejects { try db.addEvidence(.init(paperID: UUID(), note: "invalid"), to: claim.id) }
            }
            try test("Submission raw preservation, normalization and timeline ordering") {
                let time = Date().addingTimeInterval(-86400); var item = Submission(title: "A", journal: "J", submittedAt: time)
                try expect(SubmissionStatus.normalize("Required Reviews Completed") == .reviewsComplete, "Completed reviews are not under review")
                try expect(SubmissionStatus.normalize("Unfamiliar journal wording") == .unknown, "Unknown states remain unknown")
                let raw = "  Required Reviews Completed  "
                try expect(try item.record(status: .reviewsComplete, raw: raw, at: time.addingTimeInterval(10)), "First transition")
                try expect(try !item.record(status: .reviewsComplete, raw: raw, at: time.addingTimeInterval(20)), "No duplicate observation")
                try expect(item.statusRaw == raw && item.history.last?.statusRaw == raw, "Raw bytes retained")
                try rejects { try item.record(status: .accepted, raw: "Accepted", at: time) }
                try rejects { try item.record(status: .accepted, raw: "Accepted", at: Date().addingTimeInterval(3600)) }
            }
            try test("SQLite round trip, version migration and concurrent writer protection") {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: dir) }
                let url = dir.appendingPathComponent("research.sqlite")
                let first = try SQLiteRepository(url: url); var db = try first.load(); db.objects.append(ResearchObject(title: "Offline paper")); try first.save(db)
                let second = try SQLiteRepository(url: url); try expect(try second.load() == db, "Disk round trip")
                db.objects[0].title = "Newer title"; try first.save(db)
                try rejects { try second.save(ResearchDatabase()) }
                try expect(try second.load().objects[0].title == "Newer title", "Conflict leaves committed work intact")
                var invalid = db; invalid.notes = [.init(paperID: UUID(), text: "dangling")]; try rejects { try first.save(invalid) }
                try expect(try first.load() == db, "Invalid write does not replace data")
            }
            try test("Unknown SQLite schema and malformed payload do not reset research") {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
                let url = dir.appendingPathComponent("future.sqlite"); var sqlite: OpaquePointer?; sqlite3_open(url.path, &sqlite); sqlite3_exec(sqlite, "PRAGMA user_version=99", nil, nil, nil); sqlite3_close(sqlite)
                try rejects { _ = try SQLiteRepository(url: url) }
                sqlite3_open(url.path, &sqlite); sqlite3_exec(sqlite, "PRAGMA user_version=0", nil, nil, nil); sqlite3_close(sqlite)
                let repo = try SQLiteRepository(url: url); _ = try repo.load(); try repo.save(ResearchDatabase())
                sqlite3_open(url.path, &sqlite); sqlite3_exec(sqlite, "UPDATE workspace SET payload='broken'", nil, nil, nil); sqlite3_close(sqlite)
                try rejects { _ = try repo.load() }
            }
            try test("ORCID checksum and OAuth callback validation") {
                try expect(try ORCIDIdentity.normalize("https://orcid.org/0000-0002-1825-0097") == "0000-0002-1825-0097", "ORCID canonicalization")
                try rejects { _ = try ORCIDIdentity.normalize("0000-0002-1825-0098") }
                let flow = try ORCIDAuthorization(clientID: "APP-TEST", redirectURI: URL(string: "https://localhost/callback")!)
                let good = URL(string: "https://localhost/callback?code=abc&state=\(flow.state)")!
                try expect(try flow.code(from: good) == "abc", "Valid callback")
                try rejects { _ = try flow.code(from: URL(string: "https://elsewhere/callback?code=abc&state=\(flow.state)")!) }
                try rejects { _ = try flow.code(from: URL(string: "https://localhost/callback?code=abc&state=wrong")!) }
                try rejects { _ = try flow.code(from: good, now: flow.createdAt.addingTimeInterval(601)) }
                try rejects { _ = try flow.code(from: URL(string: good.absoluteString + "&code=second")!) }
            }
            try test("AcaTex exchange is versioned, portable and excludes local PDF paths") {
                var item = ResearchObject(title: "Test", authors: [.init("A. Author")], year: 2026, doi: "10.1/test")
                item.sources = [.init(provider: "local-pdf", externalID: "x", url: URL(fileURLWithPath: "/private/paper.pdf"))]
                let data = try JSONResearchBridge().export(.init(object: item, citeKey: "Author2026"))
                let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                try expect(object["schemaVersion"] as? Int == 1 && object["citeKey"] as? String == "Author2026", "Exchange contract")
                try expect(!String(decoding: data, as: UTF8.self).contains("/private/"), "No local PDF path exported")
            }
            try await networkChecks()
            if CommandLine.arguments.contains("--live") {
                let paper = ResearchObject(title: "Rationalist Explanations for War", doi: "10.1017/S0020818300033324")
                let (_, metrics) = try await OpenAlexProvider().metrics(for: paper)
                try expect(metrics.citationCount >= 0 && metrics.provider == "OpenAlex", "Live OpenAlex response")
                print("PASS Live public DOI lookup: \(metrics.citationCount) OpenAlex citations")
            }
            try test("Reading format migration preserves legacy evidence and refuses future formats") {
                var db = ResearchDatabase(); let project = ResearchProject(title: "Migration"); let paper = ResearchObject(title: "Paper")
                var claim = Claim(projectID: project.id, text: "Claim"); let evidence = Evidence(paperID: paper.id, quote: "Source")
                claim.evidence = [evidence.id]; claim.sources = [paper.id]
                db.objects = [paper]; db.projects = [project]; db.claims = [claim]; db.evidence = [evidence]; db.formatVersion = 1
                var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(db)) as! [String: Any]
                json.removeValue(forKey: "readingStates"); json.removeValue(forKey: "highlights")
                var decoded = try JSONDecoder().decode(ResearchDatabase.self, from: JSONSerialization.data(withJSONObject: json))
                try decoded.upgradeReadingFormat(); try decoded.validate()
                try expect(decoded.formatVersion == 5 && decoded.evidence[0].projectID == project.id && decoded.evidence[0].quote == "Source", "Legacy content remains linked")
                decoded.formatVersion = 999; try rejects { try decoded.upgradeReadingFormat() }
            }
            try test("Project evidence can precede a claim; attachment is idempotent and scoped") {
                var db = ResearchDatabase(); let p = ResearchProject(title: "P"), other = ResearchProject(title: "Other"), paper = ResearchObject(title: "Paper")
                let claim = Claim(projectID: p.id, text: "My independent claim"), wrong = Claim(projectID: other.id, text: "Other claim")
                db.projects = [p, other]; db.objects = [paper]; db.claims = [claim, wrong]
                let evidence = Evidence(paperID: paper.id, page: "14", quote: "Source statement")
                try db.saveEvidence(evidence, projectID: p.id); try db.validate()
                try expect(db.claims[0].evidence.isEmpty && db.objects[0].projects == [p.id], "Evidence without claim saved to project")
                try rejects { try db.attachEvidence(evidence.id, to: wrong.id) }
                try db.attachEvidence(evidence.id, to: claim.id); try db.attachEvidence(evidence.id, to: claim.id)
                try expect(db.claims[0].evidence == [evidence.id] && db.claims[0].text != evidence.quote, "Link deduplicated; claim remains independent")
            }
            try test("Reading positions clamp malformed input and retain progress offline") {
                let paper = ResearchObject(title: "Long paper")
                var position = ReadingPosition(paperID: paper.id, documentID: "hash", page: 13, pageCount: 32, normalizedScrollPosition: 1, zoom: 1.2)
                try expect(position.progress == 43, "Reading progress derives from physical page and offset")
                var db = ResearchDatabase(); db.objects = [paper]; db.savePosition(position)
                position.markedRead = true; db.savePosition(position)
                try expect(db.readingStates?.count == 1 && db.readingPosition(for: paper.id)?.progress == 100, "Manual Read is retained")
                let clamped = ReadingPosition(paperID: paper.id, documentID: "hash", page: 900, pageCount: 320, normalizedScrollPosition: .nan, zoom: .infinity)
                try expect(clamped.page == 319 && clamped.normalizedScrollPosition == 0 && clamped.zoom == 1, "Invalid persisted inputs are sanitized")
                try db.validate(); let decoded = try JSONDecoder().decode(ResearchDatabase.self, from: JSONEncoder().encode(db)); try expect(decoded == db, "Offline round trip")
            }
            try test("Reading scale remains backward compatible and validates persisted values") {
                let paper = ResearchObject(title: "Legacy reading record")
                var position = ReadingPosition(paperID: paper.id, documentID: "hash", page: 4, pageCount: 20, normalizedScrollPosition: 0.4, zoom: 1.7)
                var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(position)) as! [String: Any]
                legacy.removeValue(forKey: "readingScale")
                let decoded = try JSONDecoder().decode(ReadingPosition.self, from: JSONSerialization.data(withJSONObject: legacy))
                try expect(decoded.readingScale == nil && decoded.zoom == 1.7 && decoded.page == 4, "Old physical zoom decodes unchanged")
                position.readingScale = 1.25
                var db = ResearchDatabase(); db.objects = [paper]; db.savePosition(position); try db.validate()
                let restored = try JSONDecoder().decode(ResearchDatabase.self, from: JSONEncoder().encode(db))
                try expect(restored.readingPosition(for: paper.id)?.readingScale == 1.25, "Relative scale survives offline database round trip")
                for invalid in [-1.0, 0, 101] { position.readingScale = invalid; db.savePosition(position); try rejects { try db.validate() } }
            }
            try test("Zotero attachment endpoints and redirects never leak API credentials") {
                let source = SourceReference(provider: "zotero-pdf", externalID: "web:users/123:ABCD2345")
                try expect(try ZoteroAttachment.endpoint(for: source).absoluteString == "https://api.zotero.org/users/123/items/ABCD2345/file", "Official file endpoint")
                var first = source; first.metadata = ["md5": "", "version": "1"]
                var second = first; second.metadata["version"] = "2"
                try expect(ZoteroAttachment.cacheFilename(for: first) != ZoteroAttachment.cacheFilename(for: second), "An empty MD5 falls back to version for cache invalidation")
                try rejects { _ = try ZoteroAttachment.endpoint(for: .init(provider: "zotero-pdf", externalID: "web:users/123:../secret")) }
                var redirected = URLRequest(url: URL(string: "https://zotero.s3.amazonaws.com/signed.pdf")!)
                redirected.setValue("secret", forHTTPHeaderField: "Zotero-API-Key")
                try expect(ZoteroAttachment.redirectedRequest(redirected)?.value(forHTTPHeaderField: "Zotero-API-Key") == nil, "Cross-origin credentials stripped")
                redirected.url = URL(string: "http://zotero.s3.amazonaws.com/unsafe.pdf")
                try expect(ZoteroAttachment.redirectedRequest(redirected) == nil, "Downgrade blocked")
                redirected.url = URL(string: "https://publisher.example/file.pdf")
                try expect(ZoteroAttachment.redirectedRequest(redirected) == nil, "Publisher bypass blocked")
            }
            print("\(count) checks passed.")
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    static func networkChecks() async throws {
        let zotero = FixtureHTTP { request in
            let url = request.url!; try expect(request.value(forHTTPHeaderField: "Zotero-API-Version") == "3", "Zotero version header")
            try expect(request.value(forHTTPHeaderField: "Zotero-API-Key") == "fixture-key" && !(url.query ?? "").contains("fixture-key"), "Credential stays in header")
            if url.path.hasSuffix("collections") { return Data(#"[{"key":"COL","data":{"name":"Theory","parentCollection":false}}]"#.utf8) }
            let start = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "start" }!.value!
            if start == "0" {
                let rows: [[String: Any]] = (0..<100).map { i in ["key":"P\(i)", "version": 1, "data":["itemType":"journalArticle", "title":"Paper \(i)", "DOI":"10.1/p\(i)", "date":"2025-03-01", "creators":[["firstName":"Ada","lastName":"Smith","creatorType":"author"]], "collections":["COL"]] as [String: Any]] }
                return try JSONSerialization.data(withJSONObject: rows)
            }
            return Data(#"[{"key":"NOTE","data":{"itemType":"note","parentItem":"P0","note":"<p>Safe &amp; local</p><script>bad()</script>"}},{"key":"ABCD2345","data":{"itemType":"attachment","parentItem":"P0","contentType":"application/pdf","linkMode":"imported_file","md5":"samplehash","filename":"paper.pdf"}},{"key":"URLA2345","data":{"itemType":"attachment","parentItem":"P0","contentType":"application/pdf","linkMode":"linked_url","url":"https://publisher.example/paper.pdf"}}]"#.utf8)
        }
        let batch = try await ZoteroProvider(local: false, userID: "123", apiKey: "fixture-key", transport: zotero).importLibrary()
        try expect(batch.objects.count == 100 && batch.notes.count == 1 && batch.collections.count == 1, "Paginated import complete")
        try expect(batch.notes[0].paperID == batch.objects[0].id && batch.notes[0].text == "Safe & local", "Notes associated without active HTML")
        try expect(batch.objects[0].year == 2025 && batch.objects[0].sources[0].metadata["collections"] == "web:users/123:COL", "Metadata/collection mapping")
        try expect(batch.objects[0].sources.contains { $0.provider == "zotero-pdf" && $0.externalID == "web:users/123:ABCD2345" && $0.metadata["md5"] == "samplehash" }, "PDF attachment stays on its parent paper")
        try expect(!batch.objects[0].sources.contains { $0.externalID.contains("URLA2345") }, "Publisher link is not an attachment download")
        count += 1; print("PASS Zotero pagination, PDF attachments, safe notes and authentication headers")
        let openalex = FixtureHTTP { request in
            try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "OpenAlex bearer")
            return Data(#"{"id":"https://openalex.org/W123","title":"Paper","cited_by_count":12,"counts_by_year":[{"year":2026,"cited_by_count":5}],"abstract_inverted_index":{"Research":[0],"works.":[1]}}"#.utf8)
        }
        let (enriched, metrics) = try await OpenAlexProvider(apiKey: "fixture-key", transport: openalex).metrics(for: .init(title: "Paper", doi: "10.1/abc"))
        try expect(enriched.abstract == "Research works." && metrics.citationCount == 12 && metrics.citationsByYear[0].count == 5 && metrics.provider == "OpenAlex", "Metrics provenance and abstract reconstruction")
        count += 1; print("PASS OpenAlex decoding, annual history and provider provenance")
        let creds = MemoryCredentials(); let flow = try ORCIDAuthorization(clientID: "APP-TEST", redirectURI: URL(string: "https://localhost/")!)
        let tokenHTTP = FixtureHTTP { request in
            try expect(request.httpMethod == "POST" && request.url!.host == "orcid.org", "Official ORCID token endpoint")
            try expect(String(decoding: request.httpBody!, as: UTF8.self).contains("client_secret=a%2Bb%26c"), "Form encodes secret safely")
            return Data(#"{"access_token":"fixture-token","orcid":"0000-0002-1825-0097","name":"Fixture Researcher"}"#.utf8)
        }
        let profile = try await ORCIDOAuthClient(transport: tokenHTTP).exchange(flow, callback: URL(string: "https://localhost/?code=fixture&state=\(flow.state)")!, personalClientSecret: "a+b&c", credentials: creds)
        try expect(profile.authenticated && creds.values["orcid.accessToken"] == "fixture-token", "OAuth identity/token separation")
        count += 1; print("PASS OAuth exchange and credential-store boundary")
    }
}
