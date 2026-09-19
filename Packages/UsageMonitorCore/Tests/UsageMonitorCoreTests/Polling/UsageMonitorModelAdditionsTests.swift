import Foundation
import Testing
@testable import UsageMonitorCore

@MainActor
@Suite("UsageMonitorModel additions")
struct UsageMonitorModelAdditionsTests {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(providers: [any UsageProvider]) -> (UsageMonitorModel, InMemorySettingsStore) {
        let store = InMemorySettingsStore()
        let now = fixedNow
        let model = UsageMonitorModel(
            providers: providers, settingsStore: store, sleeper: RecordingSleeper(), now: { now }
        )
        return (model, store)
    }

    @Test func nextPollFollowsTheLastRefreshAndInterval() async {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let (model, _) = makeModel(providers: [provider])
        #expect(model.nextPollAt == nil)

        await model.refreshNow()
        #expect(model.nextPollAt == fixedNow.addingTimeInterval(120))

        model.settings.refreshInterval = .fiveMinutes
        #expect(model.nextPollAt == fixedNow.addingTimeInterval(300))
    }

    @Test func setEnabledPersistsAndTogglesVisibility() {
        let providers: [any UsageProvider] = [
            ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude))),
            ScriptedProvider(id: .grok, result: .success(.sample(provider: .grok))),
        ]
        let (model, store) = makeModel(providers: providers)

        model.setEnabled(.grok, false)
        #expect(model.visibleStatuses.map(\.provider) == [.claude])
        #expect(store.current.enabledProviders == [.claude, .openAI])
        #expect(store.saveCount == 1)

        model.setEnabled(.grok, true)
        #expect(model.visibleStatuses.map(\.provider) == [.claude, .grok])
        #expect(store.saveCount == 2)

        model.setEnabled(.grok, true)
        #expect(store.saveCount == 2, "no-op changes are not persisted")
    }

    @Test func overlappingRefreshSkipsProvidersAlreadyInFlight() async {
        let provider = GatedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let (model, _) = makeModel(providers: [provider])

        let inFlight = Task { await model.refreshNow() }
        await waitUntil { provider.fetches.total == 1 }
        #expect(model.status(for: .claude)?.isRefreshing == true)
        #expect(model.isRefreshing)

        await model.refreshNow()
        #expect(provider.fetches.total == 1, "a second refresh must not double-poll an in-flight provider")
        #expect(model.isRefreshing, "the no-op refresh must not clear the in-flight flag")

        provider.open()
        await inFlight.value
        #expect(provider.fetches.total == 1)
        #expect(model.status(for: .claude)?.snapshot != nil)
        #expect(model.status(for: .claude)?.isRefreshing == false)
        #expect(!model.isRefreshing)
    }

    @Test func diagnosticsReportConvenienceUsesModelState() async {
        let provider = ScriptedProvider(id: .openAI, result: .success(.sample(provider: .openAI, planName: "Pro")))
        let (model, _) = makeModel(providers: [provider])
        await model.refreshNow()

        let report = model.diagnosticsReport(appVersion: "0.1.0", osVersion: "macOS 27.0")

        #expect(report.contains("app_version: 0.1.0"))
        #expect(report.contains("os_version: macOS 27.0"))
        #expect(report.contains("[openai]"))
        #expect(report.contains("plan: Pro"))
        #expect(report.contains("polls: 1 successes: 1 failures: 0"))
    }
}
