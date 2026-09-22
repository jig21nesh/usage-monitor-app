import Foundation

public enum FileReadError: Error, Sendable, Hashable {
    case notFound
    case notReadable(String)
    case tooLarge(limit: Int)
    /// The file sits in the home folder and the user has not granted access yet (ADR 0009).
    case accessNotGranted
}

/// Read-only file access with a size cap, so a credential file can never be read unbounded.
public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func read(at url: URL, maxBytes: Int) throws(FileReadError) -> Data
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func read(at url: URL, maxBytes: Int) throws(FileReadError) -> Data {
        guard fileExists(at: url) else { throw .notFound }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw .notReadable("open_failed")
        }
        defer { try? handle.close() }
        let data: Data?
        do {
            data = try handle.read(upToCount: maxBytes + 1)
        } catch {
            throw .notReadable("read_failed")
        }
        let bytes = data ?? Data()
        if bytes.count > maxBytes {
            throw .tooLarge(limit: maxBytes)
        }
        return bytes
    }
}
