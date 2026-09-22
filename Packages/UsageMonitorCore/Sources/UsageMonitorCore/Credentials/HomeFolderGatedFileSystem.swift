import Foundation

/// Refuses reads inside the home folder until the user has granted access (ADR 0009), so a
/// provider reports "grant access" instead of a bare permission error. Paths outside the home
/// folder, such as an absolute `CODEX_HOME`, pass straight through.
public struct HomeFolderGatedFileSystem: FileSystem {
    private let base: any FileSystem
    private let access: any HomeFolderAccess

    public init(base: any FileSystem, access: any HomeFolderAccess) {
        self.base = base
        self.access = access
    }

    public func fileExists(at url: URL) -> Bool {
        guard !isGated(url) else { return false }
        return base.fileExists(at: url)
    }

    public func read(at url: URL, maxBytes: Int) throws(FileReadError) -> Data {
        guard !isGated(url) else { throw .accessNotGranted }
        return try base.read(at: url, maxBytes: maxBytes)
    }

    private func isGated(_ url: URL) -> Bool {
        !access.state().isGranted && HomeFolderPaths.isInside(url, home: access.expectedDirectory)
    }
}
