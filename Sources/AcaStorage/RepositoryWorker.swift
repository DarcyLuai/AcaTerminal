import Foundation
import AcaCore

/// All SQLite access and JSON encoding/decoding live on this serial utility queue.
/// The first failed save stops subsequent writes; it never skips a failed revision.
public final class RepositoryWorker {
    private let queue = DispatchQueue(label: "org.acaterminal.persistence", qos: .utility)
    private var repository: SQLiteRepository?
    private var failure: Error?
    public init() {}
    public func open(url: URL, seed: ResearchDatabase?, completion: @escaping (Result<ResearchDatabase, Error>) -> Void) {
        queue.async {
            let result = Result { () throws -> ResearchDatabase in
                let repo = try SQLiteRepository(url: url); var data = try repo.load()
                if let seed = seed, data.objects.isEmpty && data.projects.isEmpty && data.submissions.isEmpty { data = seed; try repo.save(data) }
                self.repository = repo; return data
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    public func save(_ database: ResearchDatabase, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { () throws -> Void in
                if let failure = self.failure { throw failure }
                guard let repo = self.repository else { throw CoreError.invalid("The database is not open.") }
                try repo.save(database)
            }
            if case .failure(let error) = result { self.failure = error }
            DispatchQueue.main.async { completion(result) }
        }
    }
    public func drain(_ completion: @escaping () -> Void) { queue.async { DispatchQueue.main.async(execute: completion) } }
}
