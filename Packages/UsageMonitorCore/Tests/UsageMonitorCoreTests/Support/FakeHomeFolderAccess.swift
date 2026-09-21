import Foundation
import Synchronization
@testable import UsageMonitorCore

/// Scriptable grant state for model and file-system tests; counts the calls the model makes.
final class FakeHomeFolderAccess: HomeFolderAccess, Sendable {
    let expectedDirectory: URL
    private let current: Mutex<HomeFolderGrantState>
    let activations = CallCounter()
    let grants = CallCounter()
    let revocations = CallCounter()
    /// When set, `grant` throws this instead of succeeding.
    private let failure: Mutex<HomeFolderGrantError?>

    init(
        expectedDirectory: URL = URL(filePath: "/Users/tester", directoryHint: .isDirectory),
        state: HomeFolderGrantState = .notGranted,
        grantFailure: HomeFolderGrantError? = nil
    ) {
        self.expectedDirectory = expectedDirectory
        self.current = Mutex(state)
        self.failure = Mutex(grantFailure)
    }

    func state() -> HomeFolderGrantState { current.withLock { $0 } }

    func set(_ state: HomeFolderGrantState) { current.withLock { $0 = state } }

    @discardableResult
    func activate() -> HomeFolderGrantState {
        activations.increment()
        return state()
    }

    @discardableResult
    func grant(_ folder: URL) throws(HomeFolderGrantError) -> HomeFolderGrantState {
        grants.increment()
        if let failure = failure.withLock({ $0 }) { throw failure }
        set(.granted)
        return .granted
    }

    @discardableResult
    func revoke() -> HomeFolderGrantState {
        revocations.increment()
        set(.notGranted)
        return .notGranted
    }
}

final class InMemoryBookmarkStore: BookmarkStore, Sendable {
    private let value: Mutex<Data?>

    init(_ initial: Data? = nil) {
        value = Mutex(initial)
    }

    var stored: Data? { value.withLock { $0 } }

    func load() -> Data? { stored }

    func save(_ bookmark: Data) { value.withLock { $0 = bookmark } }

    func clear() { value.withLock { $0 = nil } }
}

/// Bookmarks are the path bytes; every failure mode is switchable.
final class FakeSecurityScopedBookmarks: SecurityScopedBookmarks, Sendable {
    struct Behaviour: Sendable {
        var makeFails = false
        var resolveFails = false
        var isStale = false
        var startSucceeds = true
        /// Overrides the URL a bookmark resolves to, for a bookmark that points elsewhere.
        var resolvesTo: URL?
    }

    struct Failure: Error {}

    private let behaviour: Mutex<Behaviour>
    let starts = CallCounter()
    let stops = CallCounter()

    init(_ behaviour: Behaviour = Behaviour()) {
        self.behaviour = Mutex(behaviour)
    }

    func update(_ change: @Sendable (inout Behaviour) -> Void) {
        behaviour.withLock { change(&$0) }
    }

    func makeBookmark(for url: URL) throws -> Data {
        if behaviour.withLock(\.makeFails) { throw Failure() }
        return Data(url.path(percentEncoded: false).utf8)
    }

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        let current = behaviour.withLock { $0 }
        if current.resolveFails { throw Failure() }
        guard let path = String(bytes: bookmark, encoding: .utf8) else { throw Failure() }
        let url = current.resolvesTo ?? URL(filePath: path, directoryHint: .isDirectory)
        return (url, current.isStale)
    }

    func startAccess(_ url: URL) -> Bool {
        starts.increment()
        return behaviour.withLock(\.startSucceeds)
    }

    func stopAccess(_ url: URL) {
        stops.increment()
    }
}
