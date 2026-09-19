import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("LocalFileSystem")
struct FileSystemTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "usage-monitor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func readsSmallFile() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "auth.json")
        try Data(#"{"k":1}"#.utf8).write(to: file)
        let fileSystem = LocalFileSystem()
        #expect(fileSystem.fileExists(at: file))
        #expect(try fileSystem.read(at: file, maxBytes: 1024) == Data(#"{"k":1}"#.utf8))
    }

    @Test func missingFileIsNotFound() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "missing.json")
        let fileSystem = LocalFileSystem()
        #expect(!fileSystem.fileExists(at: file))
        #expect(throws: FileReadError.notFound) { try fileSystem.read(at: file, maxBytes: 1024) }
    }

    @Test func oversizedFileIsRejected() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "big.json")
        try Data(repeating: 0x20, count: 2048).write(to: file)
        #expect(throws: FileReadError.tooLarge(limit: 1024)) { try LocalFileSystem().read(at: file, maxBytes: 1024) }
    }

    @Test(.enabled(if: getuid() != 0, "root can read anything"))
    func unreadableFileIsReported() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "locked.json")
        try Data("secret".utf8).write(to: file)
        let path = file.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        #expect(throws: FileReadError.notReadable("open_failed")) {
            try LocalFileSystem().read(at: file, maxBytes: 1024)
        }
    }
}

@Suite("SecurityFrameworkKeychainReader")
struct KeychainReaderTests {
    @Test func missingItemReturnsNilWithoutInteraction() throws {
        let reader = SecurityFrameworkKeychainReader(allowsUserInteraction: false)
        let service = "com.curiouspilabs.UsageMonitor.tests.\(UUID().uuidString)"
        #expect(try reader.genericPassword(service: service, account: nil) == nil)
        #expect(try reader.genericPassword(service: service, account: "nobody") == nil)
    }

    @Test func missingItemReturnsNilWhenInteractionAllowed() throws {
        let reader = SecurityFrameworkKeychainReader()
        #expect(reader.allowsUserInteraction)
        let service = "com.curiouspilabs.UsageMonitor.tests.\(UUID().uuidString)"
        #expect(try reader.genericPassword(service: service, account: nil) == nil)
    }
}
