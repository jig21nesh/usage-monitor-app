import Foundation
import Testing
@testable import UsageMonitorCore

@MainActor
@Suite("UsageMonitorModel")
struct UsageMonitorModelTests {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(
        providers: [any UsageProvider],
        settings: AppSettings = .default,
        sleeper: RecordingSleeper = RecordingSleeper()
    ) -> (UsageMonitorModel, InMemorySettingsStore) {
        let store = InMemorySettingsStore(settings)
        let now = fixedNow
        let model = UsageMonitorModel(providers: providers, settingsStore: store, sleeper: sleeper, now: { now })
        return (model, store)
    }

    private func settings(enabling providers: Set<ProviderID>) -> AppSettings {
        var settings = AppSettings.default
        settings.enabledProviders = providers
        return settings
    }

    @Test func initialStatusesFollowSettings() {
        let providers: [any UsageProvider] = [
            ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude))),
            ScriptedProvider(id: .openAI, result: .success(.sample(provider: .openAI))),
            ScriptedProvider(id: .grok, result: .success(.sample(provider: .grok))),
        ]
        let (model, _) = makeModel(providers: providers, settings: settings(enabling: [.claude, .grok]))
        #expect(model.statuses.count == 3)
        #expect(model.visibleStatuses.map(\.provider) == [.claude, .grok])
        #expect(model.statuses.allSatisfy { $0.link == .unknown })
        #expect(!model.isRefreshing)
        #expect(model.lastRefreshAt == nil)
    }

    @Test func refreshNowStoresSnapshotDiagnosticsAndPlan() async {
        let snapshot = UsageSnapshot.sample(provider: .claude, planName: "Max", usedPercent: 21)
        let provider = ScriptedProvider(id: .claude, result: .success(snapshot))
        let (model, _) = makeModel(providers: [provider])

        await model.refreshNow()

        let status = try! #require(model.status(for: .claude))
        #expect(status.snapshot == snapshot)
        #expect(status.lastSuccess == snapshot.fetchedAt)
        #expect(status.lastError == nil)
        #expect(status.link == .linked(AccountInfo(planName: "Max", accountLabel: nil, origin: "Claude Code")))
        #expect(!status.isRefreshing)
        #expect(!status.isStale)
        #expect(model.diagnostics[.claude]?.polls == 1)
        #expect(model.diagnostics[.claude]?.successes == 1)
        #expect(model.diagnostics[.claude]?.lastSuccessAt == snapshot.fetchedAt)
        #expect(model.lastRefreshAt == fixedNow)
        #expect(!model.isRefreshing)
        #expect(provider.fetches.total == 1)
    }

    @Test func failureRecordsErrorAndSchedulesBackoff() async {
        let provider = ScriptedProvider(id: .openAI, result: .failure(.serverError(status: 503)))
        let (model, _) = makeModel(providers: [provider])

        await model.refreshNow()

        let status = try! #require(model.status(for: .openAI))
        #expect(status.lastError == .serverError(status: 503))
        #expect(status.nextRetryAt == fixedNow.addingTimeInterval(180))
        #expect(status.link == .unknown)
        #expect(status.snapshot == nil)
        #expect(!status.isStale)
        #expect(model.diagnostics[.openAI]?.failures == 1)
        #expect(model.diagnostics[.openAI]?.lastErrorIdentifier == "server_error:503")
    }

    @Test func consecutiveFailuresEscalateAndSuccessResets() async {
        let provider = ScriptedProvider(id: .grok, results: [
            .failure(.network("a")),
            .failure(.network("b")),
            .success(.sample(provider: .grok)),
            .failure(.network("c")),
        ])
        let (model, _) = makeModel(providers: [provider])

        await model.refreshNow()
        #expect(model.status(for: .grok)?.nextRetryAt == fixedNow.addingTimeInterval(180))
        await model.refreshNow()
        #expect(model.status(for: .grok)?.nextRetryAt == fixedNow.addingTimeInterval(360))
        await model.refreshNow()
        #expect(model.status(for: .grok)?.nextRetryAt == nil)
        #expect(model.status(for: .grok)?.isStale == false)
        await model.refreshNow()
        #expect(model.status(for: .grok)?.nextRetryAt == fixedNow.addingTimeInterval(180))
        #expect(model.status(for: .grok)?.isStale == true)
        #expect(model.status(for: .grok)?.snapshot != nil)
    }

    @Test func rateLimitHonoursRetryAfterWhenLonger() async {
        let provider = ScriptedProvider(id: .claude, result: .failure(.rateLimited(retryAfter: 900)))
        let (model, _) = makeModel(providers: [provider])
        await model.refreshNow()
        #expect(model.status(for: .claude)?.nextRetryAt == fixedNow.addingTimeInterval(900))
    }

    @Test func authFailureMarksProviderNotLinked() async {
        let provider = ScriptedProvider(id: .claude, result: .failure(.unauthorized(status: 401)))
        let (model, _) = makeModel(providers: [provider])
        await model.refreshNow()
        #expect(model.status(for: .claude)?.link == .notLinked(.unauthorized(status: 401)))
        #expect(model.status(for: .claude)?.lastError?.requiresRelink == true)
    }

    @Test func cancelledIsNeitherFailureNorBackoff() async {
        let provider = ScriptedProvider(id: .claude, result: .failure(.cancelled))
        let (model, _) = makeModel(providers: [provider])
        await model.refreshNow()
        let status = try! #require(model.status(for: .claude))
        #expect(status.lastError == nil)
        #expect(status.nextRetryAt == nil)
        #expect(!status.isRefreshing)
        #expect(model.diagnostics[.claude]?.polls == 1)
        #expect(model.diagnostics[.claude]?.failures == 0)
    }

    @Test func disabledProvidersAreNotPolled() async {
        let claude = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let openAI = ScriptedProvider(id: .openAI, result: .success(.sample(provider: .openAI)))
        let (model, _) = makeModel(providers: [claude, openAI], settings: settings(enabling: [.claude]))
        await model.refreshNow()
        #expect(claude.fetches.total == 1)
        #expect(openAI.fetches.total == 0)
        #expect(model.status(for: .openAI)?.snapshot == nil)
    }

    @Test func loopPollsThenSleepsAndSkipsProvidersInBackoff() async {
        let provider = ScriptedProvider(
            id: .claude,
            link: .linked(AccountInfo(planName: nil, accountLabel: nil, origin: "Claude Code")),
            result: .failure(.serverError(status: 500))
        )
        let sleeper = RecordingSleeper(maxSleeps: 2)
        let (model, _) = makeModel(providers: [provider], sleeper: sleeper)

        model.start()
        await model.loopTask?.value

        #expect(provider.fetches.total == 1)
        #expect(sleeper.sleeps == [.seconds(120), .seconds(120)])
        let stillLinked = AccountInfo(planName: nil, accountLabel: nil, origin: "Claude Code")
        #expect(model.status(for: .claude)?.link == .linked(stillLinked))
        #expect(model.status(for: .claude)?.lastError == .serverError(status: 500))
    }

    @Test func forcedRefreshIgnoresBackoff() async {
        let provider = ScriptedProvider(id: .claude, result: .failure(.serverError(status: 500)))
        let (model, _) = makeModel(providers: [provider])
        await model.refreshNow()
        await model.refreshNow()
        #expect(provider.fetches.total == 2)
    }

    @Test func relinkPollsOnlyWhenLinked() async {
        let linked = ScriptedProvider(
            id: .claude,
            link: .linked(AccountInfo(planName: "Max", accountLabel: nil, origin: "Claude Code")),
            result: .success(.sample(provider: .claude))
        )
        let unlinked = ScriptedProvider(
            id: .grok,
            link: .notLinked(.credentialsNotFound),
            result: .success(.sample(provider: .grok))
        )
        let (model, _) = makeModel(providers: [linked, unlinked])

        await model.relink(.claude)
        await model.relink(.grok)
        await model.relink(.openAI)

        #expect(linked.fetches.total == 1)
        #expect(model.status(for: .claude)?.snapshot != nil)
        #expect(unlinked.fetches.total == 0)
        #expect(model.status(for: .grok)?.link == .notLinked(.credentialsNotFound))
        #expect(model.status(for: .grok)?.lastError == nil)
    }

    @Test func refreshLinkStatesUpdatesEveryProvider() async {
        let info = AccountInfo(planName: "Pro", accountLabel: "me@example.com", origin: "Codex CLI")
        let providers: [any UsageProvider] = [
            ScriptedProvider(id: .openAI, link: .linked(info), result: .success(.sample(provider: .openAI))),
            ScriptedProvider(
                id: .grok,
                link: .notLinked(.credentialsExpired),
                result: .success(.sample(provider: .grok))
            ),
        ]
        let (model, _) = makeModel(providers: providers)
        await model.refreshLinkStates()
        #expect(model.status(for: .openAI)?.link == .linked(info))
        #expect(model.status(for: .grok)?.link == .notLinked(.credentialsExpired))
    }

    @Test func settingsChangesPersistAndToggleProviders() {
        let providers: [any UsageProvider] = [
            ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude))),
            ScriptedProvider(id: .openAI, result: .success(.sample(provider: .openAI))),
        ]
        let (model, store) = makeModel(providers: providers)

        model.settings.enabledProviders = [.openAI]

        #expect(store.saveCount == 1)
        #expect(store.current.enabledProviders == [.openAI])
        #expect(model.status(for: .claude)?.isEnabled == false)
        #expect(model.status(for: .openAI)?.isEnabled == true)
        #expect(model.visibleStatuses.map(\.provider) == [.openAI])

        model.settings = model.settings
        #expect(store.saveCount == 1)
    }

    @Test func startIsIdempotentAndStopClearsTheLoop() {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let (model, _) = makeModel(providers: [provider], sleeper: RecordingSleeper(maxSleeps: 1000))
        model.start()
        model.start()
        #expect(model.loopTask != nil)
        model.stop()
        #expect(model.loopTask == nil)
        model.stop()
    }

    @Test func intervalChangeWhileRunningRestartsWithNewInterval() async {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let sleeper = RecordingSleeper(maxSleeps: 1)
        let (model, store) = makeModel(providers: [provider], sleeper: sleeper)

        model.start()
        await model.loopTask?.value
        model.settings.refreshInterval = .fiveMinutes
        await model.loopTask?.value

        #expect(sleeper.sleeps == [.seconds(120), .seconds(300)])
        #expect(store.current.refreshInterval == .fiveMinutes)
        #expect(provider.fetches.total == 2)
    }
}
