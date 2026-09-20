import Foundation
import Synchronization
import Testing
@testable import UsageMonitorCore

/// A provider with a poll floor, for the model tests.
struct FlooredProvider: UsageProvider {
    let id: ProviderID
    let floor: Duration
    let fetches = CallCounter()

    var minimumPollInterval: Duration? { floor }

    func linkState() async -> LinkState { .linked(AccountInfo(planName: nil, accountLabel: nil, origin: "test")) }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        fetches.increment()
        return .sample(provider: id)
    }
}

final class MutableNow: Sendable {
    private let value: Mutex<Date>

    init(_ start: Date) {
        value = Mutex(start)
    }

    var now: Date { value.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

@MainActor
@Suite("UsageMonitorModel minimum poll interval")
struct MinimumPollIntervalTests {
    @Test func floorSkipsRepeatedPollsUntilElapsed() async {
        let clock = MutableNow(Date(timeIntervalSince1970: 1_800_000_000))
        let floored = FlooredProvider(id: .muse, floor: .seconds(900))
        let free = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        var settings = AppSettings.default
        settings.enabledProviders = [.muse, .claude]
        let model = UsageMonitorModel(
            providers: [floored, free],
            settingsStore: InMemorySettingsStore(settings),
            sleeper: RecordingSleeper(),
            now: { clock.now }
        )

        await model.refreshNow()
        await model.refreshNow()
        #expect(floored.fetches.total == 1)
        #expect(free.fetches.total == 2)

        clock.advance(by: 899)
        await model.refreshNow()
        #expect(floored.fetches.total == 1)

        clock.advance(by: 1)
        await model.refreshNow()
        #expect(floored.fetches.total == 2)
    }

    @Test func menuBarStatusReflectsCurrentSettings() async {
        let provider = ScriptedProvider(id: .openAI, result: .success(.sample(provider: .openAI, usedPercent: 85)))
        var settings = AppSettings.default
        settings.enabledProviders = [.openAI]
        let model = UsageMonitorModel(providers: [provider], settingsStore: InMemorySettingsStore(settings))
        #expect(model.menuBarStatus.provider == .openAI)
        #expect(model.menuBarStatus.level == .unknown)
        await model.refreshNow()
        #expect(model.menuBarStatus.provider == .openAI)
        #expect(model.menuBarStatus.level == .critical)
        model.settings.menuBarThresholds = MenuBarThresholds(warningPercent: 90, criticalPercent: 95)
        #expect(model.menuBarStatus.level == .ok)
    }
}
