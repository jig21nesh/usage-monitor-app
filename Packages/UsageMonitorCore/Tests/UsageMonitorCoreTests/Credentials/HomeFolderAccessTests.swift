import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("BookmarkHomeFolderAccess")
struct HomeFolderAccessTests {
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    private func makeAccess(
        store: InMemoryBookmarkStore = InMemoryBookmarkStore(),
        bookmarks: FakeSecurityScopedBookmarks = FakeSecurityScopedBookmarks()
    ) -> BookmarkHomeFolderAccess {
        BookmarkHomeFolderAccess(expectedDirectory: home, store: store, bookmarks: bookmarks)
    }

    @Test func startsNotGrantedWithoutABookmark() {
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(bookmarks: bookmarks)
        #expect(access.state() == .notGranted)
        #expect(access.activate() == .notGranted)
        #expect(bookmarks.starts.total == 0)
    }

    @Test func grantStoresTheBookmarkAndStartsAccess() throws {
        let store = InMemoryBookmarkStore()
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(store: store, bookmarks: bookmarks)

        #expect(try access.grant(home) == .granted)

        #expect(access.state() == .granted)
        #expect(store.stored == Data("/Users/tester/".utf8), "the fake bookmark is the directory path")
        #expect(bookmarks.starts.total == 1)
        // Already active: a second activate must not start a second scope.
        #expect(access.activate() == .granted)
        #expect(bookmarks.starts.total == 1)
    }

    @Test(arguments: ["/Users/tester/", "/Users/tester/./", "/Users/other/../tester"])
    func grantAcceptsSpellingsOfTheHomeFolder(path: String) throws {
        let access = makeAccess()
        #expect(try access.grant(URL(filePath: path, directoryHint: .isDirectory)) == .granted)
    }

    @Test(arguments: ["/Users/tester/Documents", "/Users/tester2", "/Users", "/"])
    func grantRefusesAnythingButTheHomeFolder(path: String) {
        let store = InMemoryBookmarkStore()
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(store: store, bookmarks: bookmarks)

        #expect(throws: HomeFolderGrantError.wrongFolder(expected: "/Users/tester")) {
            try access.grant(URL(filePath: path, directoryHint: .isDirectory))
        }
        #expect(access.state() == .notGranted)
        #expect(store.stored == nil)
        #expect(bookmarks.starts.total == 0)
    }

    @Test func activateRestoresAStoredBookmark() {
        let store = InMemoryBookmarkStore(Data("/Users/tester".utf8))
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(store: store, bookmarks: bookmarks)

        #expect(access.activate() == .granted)
        #expect(bookmarks.starts.total == 1)
    }

    @Test func staleBookmarkIsReportedAndReplacedByAFreshGrant() throws {
        let store = InMemoryBookmarkStore(Data("/Users/tester".utf8))
        let bookmarks = FakeSecurityScopedBookmarks(.init(isStale: true))
        let access = makeAccess(store: store, bookmarks: bookmarks)

        #expect(access.activate() == .stale)
        #expect(bookmarks.starts.total == 0)
        #expect(store.stored != nil, "the stale bookmark stays until the user grants or revokes")

        bookmarks.update { $0.isStale = false }
        #expect(try access.grant(home) == .granted)
        #expect(bookmarks.starts.total == 1)
    }

    @Test func revokeStopsAccessAndClearsTheStore() throws {
        let store = InMemoryBookmarkStore()
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(store: store, bookmarks: bookmarks)
        try access.grant(home)

        #expect(access.revoke() == .notGranted)

        #expect(access.state() == .notGranted)
        #expect(store.stored == nil)
        #expect(bookmarks.stops.total == 1)
        // Nothing is active any more, so a second revoke has nothing to stop.
        #expect(access.revoke() == .notGranted)
        #expect(bookmarks.stops.total == 1)
    }

    @Test func regrantStopsThePreviousScopeFirst() throws {
        let bookmarks = FakeSecurityScopedBookmarks()
        let access = makeAccess(bookmarks: bookmarks)
        try access.grant(home)
        try access.grant(home)
        #expect(bookmarks.stops.total == 1)
        #expect(bookmarks.starts.total == 2)
    }

    @Test func unresolvableBookmarkIsUnavailable() {
        let store = InMemoryBookmarkStore(Data("/Users/tester".utf8))
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(resolveFails: true)))
        #expect(access.activate() == .unavailable("resolve_failed"))
    }

    @Test func bookmarkForAnotherFolderIsUnavailable() {
        let store = InMemoryBookmarkStore(Data("/Users/tester".utf8))
        let elsewhere = URL(filePath: "/Users/other", directoryHint: .isDirectory)
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(resolvesTo: elsewhere)))
        #expect(access.activate() == .unavailable("bookmark_folder_mismatch"))
    }

    @Test func refusedStartIsUnavailable() {
        let store = InMemoryBookmarkStore(Data("/Users/tester".utf8))
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(startSucceeds: false)))
        #expect(access.activate() == .unavailable("start_access_failed"))
    }

    @Test func grantFailsWhenTheBookmarkCannotBeMade() {
        let store = InMemoryBookmarkStore()
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(makeFails: true)))
        #expect(throws: HomeFolderGrantError.bookmarkFailed("make_failed")) { try access.grant(home) }
        #expect(store.stored == nil)
    }

    @Test func grantFailsWhenTheBookmarkCannotBeResolved() {
        let store = InMemoryBookmarkStore()
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(resolveFails: true)))
        #expect(throws: HomeFolderGrantError.bookmarkFailed("resolve_failed")) { try access.grant(home) }
        #expect(access.state() == .unavailable("resolve_failed"))
        #expect(store.stored == nil)
    }

    @Test func grantFailsWhenAccessCannotStart() {
        let store = InMemoryBookmarkStore()
        let access = makeAccess(store: store, bookmarks: FakeSecurityScopedBookmarks(.init(startSucceeds: false)))
        #expect(throws: HomeFolderGrantError.accessDenied) { try access.grant(home) }
        #expect(access.state() == .unavailable("start_access_failed"))
        #expect(store.stored == nil)
    }

    @Test func statesAndErrorsHaveStableTextAndIdentifiers() {
        #expect(HomeFolderGrantState.granted.logIdentifier == "granted")
        #expect(HomeFolderGrantState.notGranted.logIdentifier == "not_granted")
        #expect(HomeFolderGrantState.stale.logIdentifier == "stale")
        #expect(HomeFolderGrantState.unavailable("x").logIdentifier == "unavailable:x")
        #expect(HomeFolderGrantState.granted.isGranted)
        #expect(!HomeFolderGrantState.stale.isGranted)
        #expect(HomeFolderGrantState.granted.userMessage == "Granted")
        #expect(HomeFolderGrantState.notGranted.userMessage == "Not granted")
        #expect(HomeFolderGrantState.stale.userMessage == "Needs to be granted again")
        #expect(HomeFolderGrantState.unavailable("x").userMessage == "Unavailable")
        #expect(HomeFolderGrantError.wrongFolder(expected: "/Users/me").userMessage.contains("/Users/me"))
        #expect(HomeFolderGrantError.bookmarkFailed("x").userMessage.contains("Try again"))
        #expect(HomeFolderGrantError.accessDenied.userMessage.contains("refused"))
        let hint = ProviderError.credentialsUnreadable(ProviderError.homeFolderNotGranted).userMessage
        #expect(hint.contains("Grant access"))
        #expect(ProviderError.credentialsUnreadable("other").userMessage == "The stored login could not be read.")
    }

    @Test func alwaysGrantedNeverChanges() throws {
        let access = AlwaysGrantedHomeFolderAccess(expectedDirectory: home)
        #expect(access.state() == .granted)
        #expect(access.activate() == .granted)
        #expect(try access.grant(URL(filePath: "/anywhere")) == .granted)
        #expect(access.revoke() == .granted)
        #expect(AlwaysGrantedHomeFolderAccess().expectedDirectory.path(percentEncoded: false).hasPrefix("/"))
    }
}

@Suite("Home folder bookmark stores and Foundation bookmarks")
struct HomeFolderBookmarkStoreTests {
    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "com.jiggykakkad.UsageMonitor.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBookmarkStore(defaults: defaults)

        #expect(store.load() == nil)
        store.save(Data([1, 2, 3]))
        #expect(store.load() == Data([1, 2, 3]))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func foundationBookmarksRoundTripARealFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "usage-monitor-bookmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmarks = FoundationSecurityScopedBookmarks()

        let data = try bookmarks.makeBookmark(for: directory)
        let resolved = try bookmarks.resolve(data)

        #expect(!data.isEmpty)
        #expect(!resolved.isStale)
        let resolvedPath = resolved.url.standardizedFileURL.resolvingSymlinksInPath()
        #expect(resolvedPath == directory.standardizedFileURL.resolvingSymlinksInPath())
        // Outside a sandbox the scope calls are no-ops; only their symmetry matters here.
        _ = bookmarks.startAccess(resolved.url)
        bookmarks.stopAccess(resolved.url)
        #expect(throws: (any Error).self) { try bookmarks.resolve(Data("not a bookmark".utf8)) }
    }
}
