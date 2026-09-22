import Foundation
import Synchronization

/// Whether the sandboxed app may read the user's home folder right now (ADR 0009).
public enum HomeFolderGrantState: Sendable, Hashable {
    case granted
    case notGranted
    /// A bookmark exists but macOS reports it stale; the user has to grant access again.
    case stale
    /// A bookmark exists but could not be turned into access. The string is a fixed identifier.
    case unavailable(String)

    public var isGranted: Bool { self == .granted }

    /// Stable identifier for logs and the Diagnostics report.
    public var logIdentifier: String {
        switch self {
        case .granted: "granted"
        case .notGranted: "not_granted"
        case .stale: "stale"
        case .unavailable(let reason): "unavailable:\(reason)"
        }
    }

    public var userMessage: String {
        switch self {
        case .granted: "Granted"
        case .notGranted: "Not granted"
        case .stale: "Needs to be granted again"
        case .unavailable: "Unavailable"
        }
    }
}

public enum HomeFolderGrantError: Error, Sendable, Hashable {
    /// The picked folder is not the home directory. Carries the expected path for the message.
    case wrongFolder(expected: String)
    /// Creating or resolving the bookmark failed. The string is a fixed identifier.
    case bookmarkFailed(String)
    /// macOS refused to start access on a bookmark it had just resolved.
    case accessDenied

    public var userMessage: String {
        switch self {
        case .wrongFolder(let expected): "Choose your home folder, \(expected), and click Grant Access."
        case .bookmarkFailed: "macOS could not remember the folder. Try again."
        case .accessDenied: "macOS refused access to the folder. Try again."
        }
    }
}

/// User-granted, persisted, read-only access to the home folder under App Sandbox.
///
/// The stored bookmark points at a folder the user chose; it is not a credential, so ADR 0002's
/// no-persistence rule is untouched. Once access starts it is process-wide and by path, which is
/// why providers keep resolving files from `UserEnvironment.homeDirectory`.
public protocol HomeFolderAccess: Sendable {
    /// The folder the user is expected to choose: the real home directory.
    var expectedDirectory: URL { get }

    func state() -> HomeFolderGrantState

    /// Resolves a stored bookmark and starts access. Called once per launch, before the first poll.
    @discardableResult
    func activate() -> HomeFolderGrantState

    /// Validates the picked folder, stores a read-only bookmark for it and starts access.
    @discardableResult
    func grant(_ folder: URL) throws(HomeFolderGrantError) -> HomeFolderGrantState

    /// Stops access and forgets the bookmark.
    @discardableResult
    func revoke() -> HomeFolderGrantState
}

/// Where the bookmark bytes live: `UserDefaults` in the app, memory in tests.
public protocol BookmarkStore: Sendable {
    func load() -> Data?
    func save(_ bookmark: Data)
    func clear()
}

/// `UserDefaults` is documented as thread-safe, hence the unchecked conformance.
public final class UserDefaultsBookmarkStore: BookmarkStore, @unchecked Sendable {
    public static let key = "com.jiggykakkad.UsageMonitor.homeFolderBookmark"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Data? { defaults.data(forKey: Self.key) }

    public func save(_ bookmark: Data) { defaults.set(bookmark, forKey: Self.key) }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}

/// The Foundation calls behind security-scoped bookmarks, behind a protocol so the grant logic
/// above them is testable without a sandbox.
public protocol SecurityScopedBookmarks: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
    func startAccess(_ url: URL) -> Bool
    func stopAccess(_ url: URL)
}

public struct FoundationSecurityScopedBookmarks: SecurityScopedBookmarks {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    public func startAccess(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }

    public func stopAccess(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// Production implementation: one bookmark, one active security scope for the process lifetime.
public final class BookmarkHomeFolderAccess: HomeFolderAccess, Sendable {
    public let expectedDirectory: URL

    private struct Slot: Sendable {
        var state: HomeFolderGrantState = .notGranted
        /// The URL access was started on; `stopAccess` needs the very same value.
        var active: URL?
    }

    private let store: any BookmarkStore
    private let bookmarks: any SecurityScopedBookmarks
    private let slot = Mutex(Slot())

    public init(
        expectedDirectory: URL = UserEnvironment.realHomeDirectory(),
        store: any BookmarkStore,
        bookmarks: any SecurityScopedBookmarks = FoundationSecurityScopedBookmarks()
    ) {
        self.expectedDirectory = expectedDirectory
        self.store = store
        self.bookmarks = bookmarks
    }

    public func state() -> HomeFolderGrantState {
        slot.withLock { $0.state }
    }

    @discardableResult
    public func activate() -> HomeFolderGrantState {
        let state = slot.withLock { (slot: inout Slot) -> HomeFolderGrantState in
            if slot.active != nil { return slot.state }
            guard let data = store.load() else {
                slot.state = .notGranted
                return slot.state
            }
            slot.state = start(bookmark: data, into: &slot)
            return slot.state
        }
        Self.log(state, via: "activate")
        return state
    }

    @discardableResult
    public func grant(_ folder: URL) throws(HomeFolderGrantError) -> HomeFolderGrantState {
        guard HomeFolderPaths.isSame(folder, as: expectedDirectory) else {
            throw .wrongFolder(expected: HomeFolderPaths.normalized(expectedDirectory))
        }
        let data: Data
        do {
            data = try bookmarks.makeBookmark(for: folder)
        } catch {
            throw .bookmarkFailed("make_failed")
        }
        let state = try slot.withLock { (slot: inout Slot) throws(HomeFolderGrantError) -> HomeFolderGrantState in
            if let active = slot.active {
                bookmarks.stopAccess(active)
                slot.active = nil
            }
            let started = start(bookmark: data, into: &slot)
            slot.state = started
            switch started {
            case .granted:
                store.save(data)
                return started
            case .unavailable("start_access_failed"):
                throw .accessDenied
            default:
                throw .bookmarkFailed("resolve_failed")
            }
        }
        Self.log(state, via: "grant")
        return state
    }

    @discardableResult
    public func revoke() -> HomeFolderGrantState {
        let state = slot.withLock { (slot: inout Slot) -> HomeFolderGrantState in
            if let active = slot.active {
                bookmarks.stopAccess(active)
            }
            slot.active = nil
            store.clear()
            slot.state = .notGranted
            return slot.state
        }
        Self.log(state, via: "revoke")
        return state
    }

    /// Resolves and starts access; on success records the active URL. Never touches the store.
    private func start(bookmark data: Data, into slot: inout Slot) -> HomeFolderGrantState {
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try bookmarks.resolve(data)
        } catch {
            return .unavailable("resolve_failed")
        }
        if resolved.isStale {
            return .stale
        }
        guard HomeFolderPaths.isSame(resolved.url, as: expectedDirectory) else {
            return .unavailable("bookmark_folder_mismatch")
        }
        guard bookmarks.startAccess(resolved.url) else {
            return .unavailable("start_access_failed")
        }
        slot.active = resolved.url
        return .granted
    }

    private static func log(_ state: HomeFolderGrantState, via action: String) {
        UsageLog.credentials.info(
            "home folder grant state=\(state.logIdentifier, privacy: .public) via=\(action, privacy: .public)"
        )
    }
}

/// For tests and unsandboxed tooling, where the home folder is readable without a grant.
public struct AlwaysGrantedHomeFolderAccess: HomeFolderAccess {
    public let expectedDirectory: URL

    public init(expectedDirectory: URL = UserEnvironment.realHomeDirectory()) {
        self.expectedDirectory = expectedDirectory
    }

    public func state() -> HomeFolderGrantState { .granted }

    @discardableResult
    public func activate() -> HomeFolderGrantState { .granted }

    @discardableResult
    public func grant(_ folder: URL) throws(HomeFolderGrantError) -> HomeFolderGrantState { .granted }

    @discardableResult
    public func revoke() -> HomeFolderGrantState { .granted }
}

/// Path comparisons that ignore trailing slashes and `.` segments, so `/Users/me/` picked in the
/// open panel matches `/Users/me` from the passwd database.
enum HomeFolderPaths {
    static func normalized(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func isSame(_ url: URL, as other: URL) -> Bool {
        normalized(url) == normalized(other)
    }

    /// True for the home folder itself and anything below it, never for a sibling with the same prefix.
    static func isInside(_ url: URL, home: URL) -> Bool {
        let path = normalized(url)
        let root = normalized(home)
        return path == root || path.hasPrefix(root + "/")
    }
}
