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
    /// Whether file-backed providers can read the home folder under the sandbox (ADR 0009).
    public private(set) var homeFolderState: HomeFolderGrantState

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
    private let wakeSource: (any SystemWakeSource)?
    private let wakeRefreshThreshold: Duration
    private let homeFolder: any HomeFolderAccess
    private var consecutiveFailures: [ProviderID: Int] = [:]
    private var lastAttemptAt: [ProviderID: Date] = [:]
    private var lastWakeRefreshAt: Date?
    private(set) var loopTask: Task<Void, Never>?
    private(set) var wakeTask: Task<Void, Never>?

    public init(
        providers: [any UsageProvider],
        settingsStore: any SettingsStore,
        sleeper: any Sleeper = ContinuousClockSleeper(),
        backoff: BackoffPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        wakeSource: (any SystemWakeSource)? = nil,
        wakeRefreshThreshold: Duration = .seconds(30),
        homeFolder: any HomeFolderAccess = AlwaysGrantedHomeFolderAccess()
    ) {
        let settings = settingsStore.load()
        self.settings = settings
        self.providers = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.settingsStore = settingsStore
        self.sleeper = sleeper
        self.backoff = backoff
        self.now = now
        self.wakeSource = wakeSource
        self.wakeRefreshThreshold = wakeRefreshThreshold
        self.homeFolder = homeFolder
        self.homeFolderState = homeFolder.state()
        self.statuses = providers.map {
            ProviderStatus(provider: $0.id, isEnabled: settings.enabledProviders.contains($0.id))
        }
    }

    public var visibleStatuses: [ProviderStatus] { statuses.filter(\.isEnabled) }

    /// When the loop will poll again, for the panel footer. Nil until the first poll completes.
    public var nextPollAt: Date? {
        lastRefreshAt?.addingTimeInterval(settings.refreshInterval.duration.timeInterval)
    }

    public func status(for id: ProviderID) -> ProviderStatus? {
        statuses.first { $0.provider == id }
    }

    public func setEnabled(_ provider: ProviderID, _ enabled: Bool) {
        var updated = settings
        if enabled {
            updated.enabledProviders.insert(provider)
        } else {
            updated.enabledProviders.remove(provider)
        }
        settings = updated
    }

    public func start() {
        // Access must be live before the first poll reads a file; activate is idempotent.
        homeFolderState = homeFolder.activate()
        if loopTask == nil {
            loopTask = Task { [weak self] in
                await self?.runLoop()
            }
        }
        if let wakeSource, wakeTask == nil {
            wakeTask = Task { [weak self] in
                for await _ in wakeSource.wakes() {
                    guard let self, !Task.isCancelled else { return }
                    await self.handleWake()
                }
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        wakeTask?.cancel()
        wakeTask = nil
    }

    /// Redacted plain-text report for the Diagnostics pane and bug reports (ADR 0006).
    public func diagnosticsReport(
        appVersion: String,
        osVersion: String,
        formatter: ResetFormatter = ResetFormatter()
    ) -> String {
        DiagnosticsReport.render(
            statuses: statuses,
            diagnostics: diagnostics,
            settings: settings,
            environment: DiagnosticsReport.Environment(
                appVersion: appVersion,
                osVersion: osVersion,
                now: now(),
                formatter: formatter
            )
        )
    }

    public func refreshNow() async {
        await poll(force: true)
    }

    /// Probes the credential stores. Nil means every provider (Onboarding and Settings, where the
    /// user is looking at the answer); start-up passes the enabled set so a switched-off
    /// provider's keychain item is never read behind the user's back.
    public func refreshLinkStates(only subset: Set<ProviderID>? = nil) async {
        for id in statuses.map(\.provider) where subset?.contains(id) ?? true {
            guard let provider = providers[id] else { continue }
            let link = await provider.linkState()
            update(id) { $0.link = link }
        }
    }

    /// Re-reads the credential store after the user logged in to the CLI again, then polls once.
    public func relink(_ id: ProviderID) async {
        guard let provider = providers[id] else { return }
        consecutiveFailures[id] = 0
        provider.forgetCredentials()
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

    /// The folder the user has to pick in the open panel: the real home directory.
    public var homeFolderDirectory: URL { homeFolder.expectedDirectory }

    /// Stores the user's folder choice, then re-probes every provider and polls once, so cards
    /// flip from "grant access" to their real state without a relaunch.
    public func grantHomeFolder(_ folder: URL) async throws(HomeFolderGrantError) {
        homeFolderState = try homeFolder.grant(folder)
        for id in statuses.map(\.provider) {
            consecutiveFailures[id] = 0
        }
        await refreshLinkStates()
        await poll(force: true)
    }

    public func revokeHomeFolder() async {
        homeFolderState = homeFolder.revoke()
        await refreshLinkStates()
    }

    /// A burst of wake notifications (lid open, display wake, network wake) must cost one poll.
    private func handleWake() async {
        let current = now()
        if let last = lastWakeRefreshAt, current.timeIntervalSince(last) < wakeRefreshThreshold.timeInterval {
            return
        }
        lastWakeRefreshAt = current
        UsageLog.polling.info("system wake; refreshing")
        await refreshNow()
    }

    private func runLoop() async {
        await refreshLinkStates(only: settings.enabledProviders)
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
                && !status.isRefreshing
                && (subset?.contains(status.provider) ?? true)
                && (force || status.nextRetryAt.map { $0 <= current } ?? true)
                && isPastMinimumInterval(status.provider, now: current)
        }.map(\.provider)
        guard !due.isEmpty else { return }
        for id in due {
            lastAttemptAt[id] = current
        }

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
        // ADR 0002: on a rejected or expired login, re-read the store once at the next poll.
        switch error {
        case .unauthorized, .credentialsExpired:
            providers[id]?.forgetCredentials()
        default:
            break
        }
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

    /// Some endpoints (Muse's key endpoint) must not be hit on every tick (ADR 0003).
    private func isPastMinimumInterval(_ id: ProviderID, now: Date) -> Bool {
        guard let minimum = providers[id]?.minimumPollInterval, let last = lastAttemptAt[id] else { return true }
        return now.timeIntervalSince(last) >= minimum.timeInterval
    }

    /// What the menu bar icon should show right now (ADR 0008).
    public var menuBarStatus: MenuBarStatus {
        MenuBarStatusResolver.resolve(statuses: statuses, settings: settings)
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
