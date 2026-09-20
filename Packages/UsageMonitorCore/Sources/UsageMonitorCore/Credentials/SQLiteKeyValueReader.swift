import Foundation
import SQLite3

public enum SQLiteReadError: Error, Sendable, Hashable {
    case notFound
    case cannotOpen(code: Int32)
    case busy
    case malformed
}

/// Read-only access to a VS Code-style key/value table (`ItemTable(key TEXT, value BLOB)`), the
/// store Cursor keeps its login in (ADR 0008). The app never writes to these databases.
public protocol SQLiteKeyValueReader: Sendable {
    /// Returns the value for `key`, nil when the row does not exist.
    func value(forKey key: String, table: String, in databaseURL: URL) throws(SQLiteReadError) -> String?
}

/// Backed by the system SQLite library. The database is opened read-only; when the owning app
/// holds it locked, a private copy (with its WAL and shared-memory siblings) is read instead so
/// a running Cursor never blocks the poll and the poll never touches Cursor's files.
public struct SystemSQLiteKeyValueReader: SQLiteKeyValueReader {
    static let busyTimeoutMilliseconds: Int32 = 500

    public init() {}

    public func value(forKey key: String, table: String, in databaseURL: URL) throws(SQLiteReadError) -> String? {
        guard FileManager.default.fileExists(atPath: databaseURL.path(percentEncoded: false)) else {
            throw .notFound
        }
        guard Self.isIdentifier(table) else { throw .malformed }
        do {
            return try Self.read(key: key, table: table, at: databaseURL)
        } catch .busy {
            let copy = try Self.copyForReading(databaseURL)
            defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
            return try Self.read(key: key, table: table, at: copy)
        }
    }

    /// Table names cannot be bound as parameters, so only plain identifiers are interpolated.
    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }

    private static func read(key: String, table: String, at url: URL) throws(SQLiteReadError) -> String? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let openCode = sqlite3_open_v2(url.path(percentEncoded: false), &database, flags, nil)
        guard openCode == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw .cannotOpen(code: openCode)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)

        // The table name is validated against an identifier pattern above; the key is bound.
        let sql = "SELECT value FROM \"\(table)\" WHERE key = ? LIMIT 1"
        var statement: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareCode == SQLITE_OK, let statement else {
            throw classify(prepareCode)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return columnText(statement, index: 0)
        case SQLITE_DONE:
            return nil
        case let code:
            throw classify(code)
        }
    }

    /// Values are declared BLOB but Cursor stores UTF-8 text; both column types are accepted.
    private static func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { String(cString: $0) }
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return "" }
            return String(data: Data(bytes: bytes, count: count), encoding: .utf8)
        default:
            return nil
        }
    }

    private static func classify(_ code: Int32) -> SQLiteReadError {
        switch code {
        case SQLITE_BUSY, SQLITE_LOCKED: .busy
        case SQLITE_NOTADB, SQLITE_CORRUPT, SQLITE_ERROR: .malformed
        default: .cannotOpen(code: code)
        }
    }

    private static func copyForReading(_ url: URL) throws(SQLiteReadError) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "usage-monitor-sqlite-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(filePath: url.path(percentEncoded: false) + suffix)
                guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                let destination = directory.appending(path: url.lastPathComponent + suffix)
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw .busy
        }
        return directory.appending(path: url.lastPathComponent)
    }
}
