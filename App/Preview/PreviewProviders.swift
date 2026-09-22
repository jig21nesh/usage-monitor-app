#if DEBUG
import Foundation
import Synchronization
import UsageMonitorCore

/// Deterministic providers for UI tests and previews. Numbers mirror the product screenshots.
enum PreviewComposition {
    static let defaultsSuite = "com.jiggykakkad.UsageMonitor.uitests"

    static func makeModel(options: LaunchOptions) -> UsageMonitorModel {
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        if options.resetDefaults || options.firstLaunch {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        if defaults.data(forKey: UserDefaultsSettingsStore.key) == nil {
            var settings = AppSettings.default
            settings.hasCompletedOnboarding = !options.firstLaunch
            // A first launch starts from the shipping defaults so onboarding's detection is exercised;
            // every other test launch starts with the linked providers already visible.
            if !options.firstLaunch, options.scenario != .notLinked {
                settings.enabledProviders = PreviewProviders.linkedProviders
            }
            store.save(settings)
        }
        return UsageMonitorModel(
            providers: PreviewProviders.providers(for: options.scenario),
            settingsStore: store,
            sleeper: IdleSleeper(),
            homeFolder: makeHomeFolderAccess(firstLaunch: options.firstLaunch)
        )
    }

    /// A first launch starts without the grant so onboarding's Grant button is exercised; other
    /// launches start granted. The path is fixed so screenshots never show a real user name.
    static func makeHomeFolderAccess(firstLaunch: Bool) -> BookmarkHomeFolderAccess {
        let home = URL(filePath: "/Users/you", directoryHint: .isDirectory)
        let store = MemoryBookmarkStore()
        let access = BookmarkHomeFolderAccess(expectedDirectory: home, store: store, bookmarks: PathBookmarks())
        if !firstLaunch {
            store.save(Data(home.path(percentEncoded: false).utf8))
            // UI-test launches never call `model.start()`, so activate here as start() would.
            access.activate()
        }
        return access
    }

    /// Runs as many polls as the scenario needs to reach its end state; the loop never starts.
    static func warmUp(_ model: UsageMonitorModel, scenario: LaunchOptions.Scenario) async {
        await model.refreshLinkStates()
        for _ in 0..<(scenario == .stale ? 2 : 1) {
            await model.refreshNow()
        }
    }
}

/// In-memory bookmark store for UI tests; nothing reaches `UserDefaults`.
nonisolated final class MemoryBookmarkStore: BookmarkStore, Sendable {
    private let value = Mutex<Data?>(nil)

    func load() -> Data? { value.withLock { $0 } }

    func save(_ bookmark: Data) { value.withLock { $0 = bookmark } }

    func clear() { value.withLock { $0 = nil } }
}

/// Bookmarks that are just the path, so UI tests never touch the real security-scope machinery.
nonisolated struct PathBookmarks: SecurityScopedBookmarks {
    func makeBookmark(for url: URL) throws -> Data { Data(url.path(percentEncoded: false).utf8) }

    struct Unreadable: Error {}

    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(bytes: bookmark, encoding: .utf8) else { throw Unreadable() }
        return (URL(filePath: path, directoryHint: .isDirectory), false)
    }

    func startAccess(_ url: URL) -> Bool { true }

    func stopAccess(_ url: URL) {}
}

/// Sleeps long enough that the poll loop never fires during a UI test, yet stays cancellable.
nonisolated struct IdleSleeper: Sleeper {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

nonisolated final class FetchCounter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock { count in
            defer { count += 1 }
            return count
        }
    }
}

nonisolated struct PreviewProvider: UsageProvider {
    let id: ProviderID
    let link: LinkState
    let results: [Result<UsageSnapshot, ProviderError>]
    private let counter = FetchCounter()

    init(id: ProviderID, link: LinkState, results: [Result<UsageSnapshot, ProviderError>]) {
        self.id = id
        self.link = link
        self.results = results
    }

    static func notLinked(_ id: ProviderID) -> PreviewProvider {
        PreviewProvider(id: id, link: .notLinked(.credentialsNotFound), results: [.failure(.credentialsNotFound)])
    }

    func linkState() async -> LinkState { link }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let index = counter.next()
        guard !results.isEmpty else { throw .network("preview_empty") }
        return try results[min(index, results.count - 1)].get()
    }
}

enum PreviewProviders {
    /// Providers that report a login in the `linked` and `stale` scenarios.
    static let linkedProviders: Set<ProviderID> = [.claude, .openAI, .grok, .copilot, .muse]

    static func providers(for scenario: LaunchOptions.Scenario) -> [any UsageProvider] {
        if scenario == .notLinked {
            return ProviderID.allCases.map(PreviewProvider.notLinked)
        }
        let now = Date()
        let claude = claudeSnapshot(now: now)
        let claudeProvider: PreviewProvider = switch scenario {
        case .linked, .notLinked:
            PreviewProvider(id: .claude, link: linked(claude), results: [.success(claude)])
        case .stale:
            PreviewProvider(id: .claude, link: linked(claude), results: [
                .success(claude), .failure(.serverError(status: 503)),
            ])
        }
        return [
            claudeProvider,
            linkedProvider(openAISnapshot(now: now)),
            linkedProvider(grokSnapshot(now: now)),
            linkedProvider(copilotSnapshot(now: now)),
            PreviewProvider.notLinked(.cursor),
            linkedProvider(museSnapshot(now: now)),
            PreviewProvider.notLinked(.opencodeGo),
        ]
    }

    private static func linkedProvider(_ snapshot: UsageSnapshot) -> PreviewProvider {
        PreviewProvider(id: snapshot.provider, link: linked(snapshot), results: [.success(snapshot)])
    }

    private static func linked(_ snapshot: UsageSnapshot) -> LinkState {
        .linked(AccountInfo(planName: snapshot.planName, accountLabel: nil, origin: snapshot.provider.credentialOrigin))
    }

    static func claudeSnapshot(now: Date) -> UsageSnapshot {
        let weekly = now.addingTimeInterval(2 * 24 * 3600 + 3 * 3600)
        return UsageSnapshot(provider: .claude, planName: "Max (20x)", windows: [
            UsageWindow(id: "claude.session", title: "Current session", kind: .session, usedPercent: 0,
                        resetsAt: now.addingTimeInterval(4 * 3600 + 50 * 60), windowDuration: 18_000),
            UsageWindow(id: "claude.weekly.all", title: "All models", kind: .weekly, usedPercent: 29,
                        resetsAt: weekly, windowDuration: 604_800),
            UsageWindow(id: "claude.weekly.fable", title: "Fable", kind: .weeklyModel, usedPercent: 56,
                        resetsAt: weekly, windowDuration: 604_800),
        ], fetchedAt: now)
    }

    static func openAISnapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .openAI, planName: "Pro", windows: [
            UsageWindow(id: "openai.session", title: "Current session", kind: .session, usedPercent: 12,
                        resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60), windowDuration: 18_000),
            UsageWindow(id: "openai.weekly", title: "Weekly usage limit", kind: .weekly, usedPercent: 58,
                        resetsAt: now.addingTimeInterval(3 * 24 * 3600 + 7 * 3600), windowDuration: 604_800),
        ], fetchedAt: now)
    }

    static func grokSnapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .grok, planName: "SuperGrok", windows: [
            UsageWindow(id: "grok.weekly", title: "Weekly usage", kind: .weekly, usedPercent: 4,
                        resetsAt: now.addingTimeInterval(5 * 24 * 3600), windowDuration: 604_800),
        ], fetchedAt: now)
    }

    static func copilotSnapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .copilot, planName: "Copilot Pro", windows: [
            UsageWindow(id: "copilot.monthly", title: "Premium requests", kind: .monthly, usedPercent: 40,
                        resetsAt: now.addingTimeInterval(12 * 24 * 3600), windowDuration: 30 * 86_400),
        ], fetchedAt: now)
    }

    static func museSnapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .muse, planName: "High Usage", windows: [
            UsageWindow(id: "muse.session", title: "Current session", kind: .session, usedPercent: 12,
                        resetsAt: now.addingTimeInterval(3 * 3600 + 5 * 60), windowDuration: 18_000),
            UsageWindow(id: "muse.weekly", title: "Weekly usage", kind: .weekly, usedPercent: 30,
                        resetsAt: now.addingTimeInterval(4 * 24 * 3600), windowDuration: 604_800),
        ], fetchedAt: now)
    }
}
#endif
