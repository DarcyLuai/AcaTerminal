import Foundation
import AcaCore
import AcaConnectors

@main struct DiscoveryLiveChecks {
    static func main() async throws {
        let start = Date()
        let provider = OpenAlexDiscoveryProvider()
        let request = DiscoveryRequest(seedIDs: ["10.48550/arXiv.2205.01833"])
        let batch = try await provider.discover(request)
        guard batch.seeds.count == 1, !batch.works.isEmpty else { throw CoreError.invalid("No public discovery results") }
        print("LIVE OpenAlex: \(batch.seeds[0].id); \(batch.works.count) candidates (before dedup); \(Set(batch.works.map(\.id)).count) unique; \(Int(Date().timeIntervalSince(start)*1000)) ms")
        print("LIVE filters: related IDs, cites, primary_topic.id, authorships.author.id")
        print("LIVE public response metadata: \(batch.works.filter { !$0.references.isEmpty }.count) with reference IDs; \(batch.works.filter { !$0.object.abstract.isEmpty }.count) with abstracts")
    }
}
