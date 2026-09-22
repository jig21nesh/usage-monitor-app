import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("HomeFolderGatedFileSystem")
struct HomeFolderGatedFileSystemTests {
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    private let inside = URL(filePath: "/Users/tester/.codex/auth.json")
    private let sibling = URL(filePath: "/Users/tester2/.codex/auth.json")
    private let outside = URL(filePath: "/opt/codex/auth.json")

    private func makeFileSystem(state: HomeFolderGrantState) -> (HomeFolderGatedFileSystem, FakeHomeFolderAccess) {
        var base = FakeFileSystem()
        base.add(inside, contents: "{}")
        base.add(sibling, contents: "{}")
        base.add(outside, contents: "{}")
        let access = FakeHomeFolderAccess(expectedDirectory: home, state: state)
        return (HomeFolderGatedFileSystem(base: base, access: access), access)
    }

    @Test(arguments: [HomeFolderGrantState.notGranted, .stale, .unavailable("resolve_failed")])
    func homeFilesAreGatedUntilGranted(state: HomeFolderGrantState) {
        let (fileSystem, _) = makeFileSystem(state: state)
        #expect(!fileSystem.fileExists(at: inside))
        #expect(throws: FileReadError.accessNotGranted) { try fileSystem.read(at: inside, maxBytes: 1024) }
        #expect(throws: FileReadError.accessNotGranted) { try fileSystem.read(at: home, maxBytes: 1024) }
    }

    @Test func pathsOutsideTheHomeFolderPassThrough() throws {
        let (fileSystem, _) = makeFileSystem(state: .notGranted)
        #expect(fileSystem.fileExists(at: outside))
        #expect(try fileSystem.read(at: outside, maxBytes: 1024) == Data("{}".utf8))
        // A sibling that merely shares the prefix is not inside the home folder.
        #expect(fileSystem.fileExists(at: sibling))
        #expect(try fileSystem.read(at: sibling, maxBytes: 1024) == Data("{}".utf8))
    }

    @Test func grantedReadsPassThroughIncludingErrors() throws {
        let (fileSystem, _) = makeFileSystem(state: .granted)
        #expect(fileSystem.fileExists(at: inside))
        #expect(try fileSystem.read(at: inside, maxBytes: 1024) == Data("{}".utf8))
        #expect(throws: FileReadError.notFound) {
            try fileSystem.read(at: URL(filePath: "/Users/tester/.grok/auth.json"), maxBytes: 1024)
        }
        #expect(throws: FileReadError.tooLarge(limit: 1)) { try fileSystem.read(at: inside, maxBytes: 1) }
    }

    @Test func gateFollowsTheLiveState() throws {
        let (fileSystem, access) = makeFileSystem(state: .notGranted)
        #expect(throws: FileReadError.accessNotGranted) { try fileSystem.read(at: inside, maxBytes: 1024) }
        access.set(.granted)
        #expect(try fileSystem.read(at: inside, maxBytes: 1024) == Data("{}".utf8))
        access.set(.notGranted)
        #expect(!fileSystem.fileExists(at: inside))
    }

    @Test func pathHelpersNormaliseTrailingSlashesAndDotSegments() {
        let trailing = URL(filePath: "/Users/tester/", directoryHint: .isDirectory)
        #expect(HomeFolderPaths.normalized(trailing) == "/Users/tester")
        #expect(HomeFolderPaths.normalized(URL(filePath: "/", directoryHint: .isDirectory)) == "/")
        #expect(HomeFolderPaths.isSame(URL(filePath: "/Users/tester/./"), as: home))
        #expect(HomeFolderPaths.isInside(home, home: home))
        #expect(HomeFolderPaths.isInside(inside, home: home))
        #expect(!HomeFolderPaths.isInside(sibling, home: home))
        #expect(!HomeFolderPaths.isInside(URL(filePath: "/Users"), home: home))
    }
}
