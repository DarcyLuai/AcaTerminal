import Foundation
import AcaCore
import AcaStorage

/// Explicit, isolated UI fixture tool; never linked into the application.
@main struct ImpactFixtures {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: ImpactFixtures NEW_DATABASE PDF_FIXTURE") }
        let url = URL(fileURLWithPath: CommandLine.arguments[1]); guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Refusing to replace an existing database") }
        let pdf = URL(fileURLWithPath: CommandLine.arguments[2])
        var db = ResearchDatabase(); let project = ResearchProject(title: "QA research project"); db.projects = [project]
        var works: [ResearchObject] = []
        for i in 0..<120 {
            var work = ResearchObject(title: ["Temporal Dynamics of International Crises", "Democratic Peace and Domestic Institutions", "Research Methods and Evidence"][i % 3] + (i < 3 ? "" : " \(i + 1)"), authors: [.init("QA Researcher")], year: 2020 + i % 7)
            work.sources = [.init(provider: "openalex", externalID: "https://openalex.org/W\(10000000 + i)"), .init(provider: "local-pdf", externalID: work.id.uuidString, url: pdf, metadata: ["paperVersion": "accepted", "accessType": "openAccess", "fullTextProvider": "QA Repository"])]
            works.append(work)
            for day in 0..<5 { db.citationSnapshots.append(.init(objectID: work.id, metrics: .init(citationCount: 120-i+day, updatedAt: Date().addingTimeInterval(Double(day-4)*7*86400), provider: "OpenAlex"))) }
        }
        db.objects = works
        db.identity = .init(name: "QA Researcher · synthetic fixture", orcid: "0000-0002-1825-0097", metrics: .init(citationCount: 126, hIndex: 5, worksCount: 120, citationsByYear: [.init(year: 2023, count: 12), .init(year: 2024, count: 28), .init(year: 2025, count: 52), .init(year: 2026, count: 34)], provider: "OpenAlex"), works: works)
        var state = ImpactRefreshState(); state.lastAttempt = Date(); state.lastCompleted = Date(); db.impactRefresh = state
        var citer = ResearchObject(title: "Who Cites Research? A Follow-up Study", authors: [.init("Smith"), .init("Wang")], year: 2026)
        citer.abstract = "Synthetic verification text. This record is confined to the isolated QA workspace."
        citer.sources = [.init(provider: "local-pdf", externalID: "qa", url: pdf)]
        db.citationEvents = (0..<3).map { i in var event = CitationEvent(citedWorkID: works[i].id, work: .init(id: "QA-CITER-\(i)", object: citer, publicationDate: Date()), provider: "openalex", detectedAt: Date()); event.notificationClaimedAt = Date(); return event }
        let repo = try SQLiteRepository(url: url); _ = try repo.load(); try repo.save(db)
        print("Created isolated UI fixture: 120 works, 600 snapshots, 3 events")
    }
}
