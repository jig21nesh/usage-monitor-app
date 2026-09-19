import Foundation
@testable import UsageMonitorCore

struct FakeKeychainReader: KeychainReader {
    var items: [String: Data] = [:]
    var error: KeychainReadError?

    func genericPassword(service: String, account: String?) throws(KeychainReadError) -> Data? {
        if let error { throw error }
        return items[service]
    }
}

struct FakeFileSystem: FileSystem {
    var files: [String: Data] = [:]
    var unreadable: Set<String> = []

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    mutating func add(_ url: URL, contents: String) {
        files[Self.key(url)] = Data(contents.utf8)
    }

    func fileExists(at url: URL) -> Bool {
        let key = Self.key(url)
        return files[key] != nil || unreadable.contains(key)
    }

    func read(at url: URL, maxBytes: Int) throws(FileReadError) -> Data {
        let key = Self.key(url)
        if unreadable.contains(key) { throw .notReadable("fake") }
        guard let data = files[key] else { throw .notFound }
        if data.count > maxBytes { throw .tooLarge(limit: maxBytes) }
        return data
    }
}
