#if DEBUG
import Foundation
import Synchronization
import UsageMonitorCore

/// Deterministic providers for UI tests and previews. Numbers mirror the product screenshots.
enum PreviewComposition {
    static let defaultsSuite = "com.curiouspilabs.UsageMonitor.uitests"

    static func makeModel(options: LaunchOptions) -> UsageMonitorModel {
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        if options.resetDefaults || options.firstLaunch {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        if defaults.data(forKey: UserDefaultsSettingsStore.key) == nil {
            var settings = AppSettings.default
            settings.hasCompletedOnboarding = !options.firstLaunch
            store.save(settings)
        }
        return UsageMonitorModel(
            providers: PreviewProviders.providers(for: options.scenario),
            settingsStore: store,
            sleeper: IdleSleeper()
        )
    }

    /// Runs as many polls as the scenario needs to reach its end state; the loop never starts.
    static func warmUp(_ model: UsageMonitorModel, scenario: LaunchOptions.Scenario) async {
        await model.refreshLinkStates()
        for _ in 0..<(scenario == .stale ? 2 : 1) {
            await model.refreshNow()
        }
    }
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

    func linkState() async -> LinkState { link }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let index = counter.next()
        guard !results.isEmpty else { throw .network("preview_empty") }
        return try results[min(index, results.count - 1)].get()
    }
}

enum PreviewProviders {
    static func providers(for scenario: LaunchOptions.Scenario) -> [any UsageProvider] {
        let now = Date()
        let claude = claudeSnapshot(now: now)
        let openAI = openAISnapshot(now: now)
        let grok = grokSnapshot(now: now)
        let claudeProvider: PreviewProvider = switch scenario {
        case .linked:
            PreviewProvider(id: .claude, link: linked(claude), results: [.success(claude)])
        case .notLinked:
            PreviewProvider(
                id: .claude,
                link: .notLinked(.credentialsNotFound),
                results: [.failure(.credentialsNotFound)]
            )
        case .stale:
            PreviewProvider(id: .claude, link: linked(claude), results: [
                .success(claude), .failure(.serverError(status: 503)),
            ])
        }
        return [
            claudeProvider,
            PreviewProvider(id: .openAI, link: linked(openAI), results: [.success(openAI)]),
            PreviewProvider(id: .grok, link: linked(grok), results: [.success(grok)]),
        ]
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
}
#endif
