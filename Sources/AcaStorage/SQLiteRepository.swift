import Foundation
import CSQLite
import AcaCore

/// One transactional document in SQLite, intentionally small for v0.1.
/// Access from one serial owner. Revision checks prevent a second process overwriting newer work.
public final class SQLiteRepository: ResearchRepository {
    private var handle: OpaquePointer?
    private var revision: Int64 = 0
    private let fileURL: URL
    public init(url: URL) throws {
        fileURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { sqlite3_close(handle); handle = nil; throw CoreError.invalid("Unable to open the research database.") }
        do {
            sqlite3_busy_timeout(handle, 3000)
            let version = try scalar("PRAGMA user_version")
            guard version <= 1 else { throw CoreError.invalid("This database belongs to a newer AcaTerminal. Upgrade before opening it.") }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            if version == 0 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL, revision INTEGER NOT NULL)")
                    try execute("PRAGMA user_version=1"); try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { sqlite3_close(handle) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw CoreError.invalid("Database operation failed: \(String(cString: sqlite3_errmsg(handle)))") }
    }
    private func scalar(_ sql: String) throws -> Int64 {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw CoreError.invalid("Cannot read database version.") }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw CoreError.invalid("Cannot read database revision.") }
        return status == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
    }
    public func load() throws -> ResearchDatabase {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload, revision FROM workspace WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw CoreError.invalid("Cannot read the research database.") }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { revision = 0; return ResearchDatabase() }
        guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw CoreError.invalid("Research database is unreadable. It has not been reset.") }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        var database = try JSONDecoder().decode(ResearchDatabase.self, from: data)
        if (1...4).contains(database.formatVersion) {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("migration-format-\(database.formatVersion)-\(sqlite3_column_int64(statement, 1)).json")
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
        }
        try database.upgradeReadingFormat()
        try database.validate()
        revision = sqlite3_column_int64(statement, 1); return database
    }
    public func save(_ database: ResearchDatabase) throws {
        guard database.formatVersion == 5 else { throw CoreError.invalid("Unsupported workspace format.") }
        try database.validate()
        let data = try JSONEncoder().encode(database)
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try scalar("SELECT revision FROM workspace WHERE id=1")
            guard current == revision else { throw CoreError.invalid("Another AcaTerminal window or process saved changes. Reopen the app before editing; this change was not saved.") }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT INTO workspace(id,payload,revision) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, revision=excluded.revision", -1, &statement, nil) == SQLITE_OK else { throw CoreError.invalid("Cannot prepare database save.") }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let result = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(data.count), transient) }
            guard result == SQLITE_OK, sqlite3_bind_int64(statement, 2, revision + 1) == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw CoreError.invalid("Could not save changes. Check free disk space.") }
            try execute("COMMIT"); revision += 1
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
