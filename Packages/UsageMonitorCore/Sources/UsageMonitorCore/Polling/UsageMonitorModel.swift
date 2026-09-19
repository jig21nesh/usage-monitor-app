import Foundation
import Observation

/// Single source of truth for the UI (ADR 0001). Owns the poll loop, applies backoff per
/// provider, persists settings and keeps per-provider diagnostics.
@MainActor
@Observable
public final class UsageMonitorModel {
    public private(set) var statuses: [ProviderStatus]
    public private(set) var diagnostics: [ProviderID: ProviderDiagnostics] = [:]
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshAt: Date?

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            applyEnabledProviders()
            if settings.refreshInterval != oldValue.refreshInterval, loopTask != nil {
                stop()
                start()
            }
        }
    }

    private let providers: [ProviderID: any UsageProvider]
    private let settingsStore: any SettingsStore
    private let sleeper: any Sleeper
    private let backoff: BackoffPolicy
    private let now: @Sendable () -> Date
    private var consecutiveFailures: [ProviderID: Int] = [:]
    private(set) var loopTask: Task<Void, Never>?

    public init(
        providers: [any UsageProvider],
        settingsStore: any SettingsStore,
        sleeper: any Sleeper = ContinuousClockSleeper(),
        backoff: BackoffPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let settings = settingsStore.load()
        self.settings = settings
        self.providers = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.settingsStore = settingsStore
        self.sleeper = sleeper
        self.backoff = backoff
        self.now = now
        self.statuses = providers.map {
            ProviderStatus(provider: $0.id, isEnabled: settings.enabledProviders.contains($0.id))
        }
    }

    public var visibleStatuses: [ProviderStatus] { statuses.filter(\.isEnabled) }

    public func status(for id: ProviderID) -> ProviderStatus? {
        statuses.first { $0.provider == id }
    }

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    public func refreshNow() async {
        await poll(force: true)
    }

    public func refreshLinkStates() async {
        for id in statuses.map(\.provider) {
            guard let provider = providers[id] else { continue }
            let link = await provider.linkState()
            update(id) { $0.link = link }
        }
    }

    /// Re-reads the credential store after the user logged in to the CLI again, then polls once.
    public func relink(_ id: ProviderID) async {
        guard let provider = providers[id] else { return }
        consecutiveFailures[id] = 0
        let link = await provider.linkState()
        update(id) {
            $0.link = link
            $0.lastError = nil
            $0.nextRetryAt = nil
        }
        if link.isLinked {
            await poll(only: [id], force: true)
        }
    }

    private func runLoop() async {
        await refreshLinkStates()
        while !Task.isCancelled {
            await poll(force: false)
            do {
                try await sleeper.sleep(for: settings.refreshInterval.duration)
            } catch {
                return
            }
        }
    }

    private func poll(only subset: Set<ProviderID>? = nil, force: Bool) async {
        let current = now()
        let due = statuses.filter { status in
            status.isEnabled
                && (subset?.contains(status.provider) ?? true)
                && (force || status.nextRetryAt.map { $0 <= current } ?? true)
        }.map(\.provider)
        guard !due.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }
        for id in due {
            update(id) { $0.isRefreshing = true }
        }
        await withTaskGroup(of: PollOutcome.self) { group in
            for id in due {
                guard let provider = providers[id] else { continue }
                group.addTask { await Self.fetch(provider) }
            }
            for await outcome in group {
                apply(outcome)
            }
        }
        lastRefreshAt = now()
    }

    private struct PollOutcome: Sendable {
        let provider: ProviderID
        let result: Result<UsageSnapshot, ProviderError>
        let duration: Duration
    }

    private nonisolated static func fetch(_ provider: any UsageProvider) async -> PollOutcome {
        let clock = ContinuousClock()
        let started = clock.now
        let signpost = UsageLog.signposter.beginInterval("poll", id: UsageLog.signposter.makeSignpostID())
        defer { UsageLog.signposter.endInterval("poll", signpost) }
        do {
            let snapshot = try await provider.fetchUsage()
            return PollOutcome(provider: provider.id, result: .success(snapshot), duration: clock.now - started)
        } catch {
            return PollOutcome(provider: provider.id, result: .failure(error), duration: clock.now - started)
        }
    }

    private func apply(_ outcome: PollOutcome) {
        var diagnostic = diagnostics[outcome.provider] ?? ProviderDiagnostics()
        diagnostic.polls += 1
        diagnostic.lastDuration = outcome.duration
        switch outcome.result {
        case .success(let snapshot):
            applySuccess(snapshot, to: outcome.provider, diagnostic: &diagnostic, duration: outcome.duration)
        case .failure(.cancelled):
            update(outcome.provider) { $0.isRefreshing = false }
        case .failure(let error):
            applyFailure(error, to: outcome.provider, diagnostic: &diagnostic)
        }
        diagnostics[outcome.provider] = diagnostic
    }

    private func applySuccess(
        _ snapshot: UsageSnapshot,
        to id: ProviderID,
        diagnostic: inout ProviderDiagnostics,
        duration: Duration
    ) {
        consecutiveFailures[id] = 0
        diagnostic.successes += 1
        diagnostic.lastSuccessAt = snapshot.fetchedAt
        diagnostic.lastErrorIdentifier = nil
        update(id) { status in
            status.snapshot = snapshot
            status.lastError = nil
            status.lastSuccess = snapshot.fetchedAt
            status.nextRetryAt = nil
            status.isRefreshing = false
            if let plan = snapshot.planName {
                status.link = .linked(AccountInfo(
                    planName: plan,
                    accountLabel: status.link.account?.accountLabel,
                    origin: id.credentialOrigin
                ))
            }
        }
        let durationMs = duration.milliseconds
        // swiftlint:disable:next line_length
        UsageLog.polling.info("poll ok provider=\(id.rawValue, privacy: .public) duration_ms=\(durationMs, privacy: .public)")
    }

    private func applyFailure(_ error: ProviderError, to id: ProviderID, diagnostic: inout ProviderDiagnostics) {
        let failures = (consecutiveFailures[id] ?? 0) + 1
        consecutiveFailures[id] = failures
        diagnostic.failures += 1
        diagnostic.lastErrorIdentifier = error.logIdentifier
        let delay = backoff.delay(afterConsecutiveFailures: failures, retryAfter: error.retryAfterHint)
        let retryAt = now().addingTimeInterval(delay.timeInterval)
        update(id) { status in
            status.lastError = error
            status.nextRetryAt = retryAt
            status.isRefreshing = false
            if error.requiresRelink {
                status.link = .notLinked(error)
            }
        }
        let retrySeconds = Int(delay.timeInterval)
        let identifier = error.logIdentifier
        // swiftlint:disable:next line_length
        UsageLog.polling.error("poll failed provider=\(id.rawValue, privacy: .public) error=\(identifier, privacy: .public) retry_in_s=\(retrySeconds, privacy: .public)")
    }

    private func update(_ id: ProviderID, _ mutate: (inout ProviderStatus) -> Void) {
        guard let index = statuses.firstIndex(where: { $0.provider == id }) else { return }
        mutate(&statuses[index])
    }

    private func applyEnabledProviders() {
        for index in statuses.indices {
            statuses[index].isEnabled = settings.enabledProviders.contains(statuses[index].provider)
        }
    }
}
