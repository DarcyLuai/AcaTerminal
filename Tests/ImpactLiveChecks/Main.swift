import Foundation
import AcaCore
import AcaConnectors

@main struct ImpactLiveChecks {
    static func main() async {
        let client = HTTPClient()
        let provider = OpenAlexProvider(transport: client)
        var failures = 0
        do {
            let (work, metrics) = try await provider.metrics(for: ResearchObject(title: "OpenAlex", doi: "10.48550/arXiv.2205.01833"))
            let locations = try await provider.resolve(work)
            print("LIVE OpenAlex DOI lookup: \(metrics.citationCount) citations; \(locations.count) locations; versions \(Set(locations.map { $0.version.rawValue }).sorted())")
        } catch { failures += 1; print("LIVE OpenAlex lookup unavailable: \(error.localizedDescription)") }
        do {
            // Find one public, lightly cited work to keep verification inexpensive.
            let url = URL(string: "https://api.openalex.org/works?filter=publication_year:2025,cited_by_count:1&per_page=1&select=id,title,cited_by_count")!
            let data = try await client.data(for: URLRequest(url: url))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let row = (json?["results"] as? [[String: Any]])?.first, let id = row["id"] as? String else { throw CoreError.invalid("No verification work returned.") }
            var work = ResearchObject(title: row["title"] as? String ?? "Public work"); work.sources = [.init(provider: "openalex", externalID: id)]
            let state = try await provider.citationState(for: work)
            var database = ResearchDatabase(); database.objects = [work]
            let baseline = try database.applyCitationObservation(state)
            let repeatEvents = try database.applyCitationObservation(state)
            print("LIVE OpenAlex citing-work lookup: \(id); \(state.citingWorks.count) citing IDs; baseline events \(baseline.count); repeated events \(repeatEvents.count)")
        } catch { failures += 1; print("LIVE Citing-work lookup unavailable: \(error.localizedDescription)") }
        do {
            var work = ResearchObject(title: "OpenAlex preprint"); work.arxivID = "2205.01833"
            let locations = try await ArxivFullTextProvider().resolve(work)
            let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? NSTemporaryDirectory()).appendingPathComponent("Live-OA")
            let file = try await FullTextDownload.download(locations[0], directory: directory)
            print("LIVE arXiv OA PDF downloaded: \(file.lastPathComponent); \((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) bytes; preprint")
        } catch { failures += 1; print("LIVE OA download unavailable: \(error.localizedDescription)") }
        if let email = ProcessInfo.processInfo.environment["ACA_UNPAYWALL_EMAIL"], !email.isEmpty {
            do { let locations = try await UnpaywallFullTextProvider(email: email, transport: client).resolve(.init(title: "Public paper", doi: "10.1371/journal.pone.0000308")); print("LIVE Unpaywall: \(locations.count) locations") }
            catch { failures += 1; print("LIVE Unpaywall unavailable: \(error.localizedDescription)") }
        } else { print("NOT RUN Unpaywall: no contact email supplied") }
        print("Live checks unavailable/failed: \(failures)")
    }
}
