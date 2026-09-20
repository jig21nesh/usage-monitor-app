import Foundation
import SQLite3
import Testing
@testable import UsageMonitorCore

@Suite("SystemSQLiteKeyValueReader")
struct SQLiteKeyValueReaderTests {
    private let reader = SystemSQLiteKeyValueReader()

    /// Creates a VS Code-style state database. Returns the file URL; the caller removes the directory.
    private func makeDatabase(
        wal: Bool = false,
        rows: [(String, String)],
        blobRows: [(String, Data)] = []
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "sqlite-reader-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "state.vscdb")
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path(percentEncoded: false), &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        if wal {
            #expect(sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        }
        let schema = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
        #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (key, value) in rows {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(database, "INSERT INTO ItemTable (key, value) VALUES (?, ?);", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            sqlite3_bind_text(statement, 2, value, -1, transient)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        for (key, value) in blobRows {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(database, "INSERT INTO ItemTable (key, value) VALUES (?, ?);", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, key, -1, transient)
            value.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(value.count), transient)
            }
            #expect(sqlite3_step(statement) == SQLITE_DONE)
            sqlite3_finalize(statement)
        }
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func readsTextAndBlobValues() throws {
        let url = try makeDatabase(
            rows: [("cursorAuth/accessToken", "header.payload.sig"), ("cursorAuth/cachedEmail", "a@b.c")],
            blobRows: [("cursorAuth/stripeMembershipType", Data("pro".utf8)), ("empty", Data())]
        )
        defer { cleanup(url) }
        #expect(try reader.value(forKey: "cursorAuth/accessToken", table: "ItemTable", in: url) == "header.payload.sig")
        #expect(try reader.value(forKey: "cursorAuth/cachedEmail", table: "ItemTable", in: url) == "a@b.c")
        #expect(try reader.value(forKey: "cursorAuth/stripeMembershipType", table: "ItemTable", in: url) == "pro")
        #expect(try reader.value(forKey: "empty", table: "ItemTable", in: url) == "")
        #expect(try reader.value(forKey: "missing", table: "ItemTable", in: url) == nil)
    }

    @Test func readsAWriteAheadLogDatabase() throws {
        let url = try makeDatabase(wal: true, rows: [("k", "v")])
        defer { cleanup(url) }
        #expect(try reader.value(forKey: "k", table: "ItemTable", in: url) == "v")
    }

    @Test func missingFileIsNotFound() {
        let url = FileManager.default.temporaryDirectory.appending(path: "does-not-exist-\(UUID().uuidString).vscdb")
        #expect(throws: SQLiteReadError.notFound) { try reader.value(forKey: "k", table: "ItemTable", in: url) }
    }

    @Test func nonDatabaseFileIsMalformed() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "garbage-\(UUID().uuidString).vscdb")
        try Data("this is not sqlite".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: SQLiteReadError.malformed) { try reader.value(forKey: "k", table: "ItemTable", in: url) }
    }

    @Test func missingTableIsMalformed() throws {
        let url = try makeDatabase(rows: [("k", "v")])
        defer { cleanup(url) }
        #expect(throws: SQLiteReadError.malformed) { try reader.value(forKey: "k", table: "OtherTable", in: url) }
    }

    @Test(arguments: ["Item Table", "Item;Table", "1Table", "", "Item\"Table", "ItemTable--"])
    func tableNamesThatAreNotIdentifiersAreRejectedBeforeAnyQuery(table: String) throws {
        let url = try makeDatabase(rows: [("k", "v")])
        defer { cleanup(url) }
        #expect(!SystemSQLiteKeyValueReader.isIdentifier(table))
        #expect(throws: SQLiteReadError.malformed) { try reader.value(forKey: "k", table: table, in: url) }
    }

    @Test func keyIsBoundNotInterpolated() throws {
        let url = try makeDatabase(rows: [("k' OR 1=1 --", "injected"), ("k", "plain")])
        defer { cleanup(url) }
        #expect(try reader.value(forKey: "k' OR 1=1 --", table: "ItemTable", in: url) == "injected")
        #expect(try reader.value(forKey: "k", table: "ItemTable", in: url) == "plain")
    }

    @Test func lockedDatabaseIsReadFromAPrivateCopy() throws {
        let url = try makeDatabase(rows: [("k", "v")])
        defer { cleanup(url) }
        var writer: OpaquePointer?
        #expect(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        #expect(sqlite3_exec(writer, "BEGIN EXCLUSIVE;", nil, nil, nil) == SQLITE_OK)
        #expect(try reader.value(forKey: "k", table: "ItemTable", in: url) == "v")
        #expect(sqlite3_exec(writer, "COMMIT;", nil, nil, nil) == SQLITE_OK)
    }
}
