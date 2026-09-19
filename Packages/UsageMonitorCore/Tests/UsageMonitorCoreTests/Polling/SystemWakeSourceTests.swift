import AppKit
import Foundation
import Synchronization
import Testing
@testable import UsageMonitorCore

@Suite("WorkspaceWakeSource")
struct WorkspaceWakeSourceTests {
    /// The forwarder subscribes asynchronously, so the poster repeats until the stream delivers.
    @Test func forwardsWorkspaceWakeNotifications() async {
        let stream = WorkspaceWakeSource().wakes()
        let delivered = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                for _ in 0..<600 where !Task.isCancelled {
                    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(delivered)
    }
}

@MainActor
@Suite("UsageMonitorModel wake handling")
struct UsageMonitorModelWakeTests {
    final class MutableClock: Sendable {
        private let value: Mutex<Date>

        init(_ date: Date) {
            value = Mutex(date)
        }

        var now: Date { value.withLock { $0 } }

        func advance(by seconds: TimeInterval) {
            value.withLock { $0 = $0.addingTimeInterval(seconds) }
        }
    }

    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(
        provider: any UsageProvider,
        wake: FakeWakeSource,
        clock: MutableClock,
        sleeper: RecordingSleeper = RecordingSleeper(maxSleeps: 1)
    ) -> UsageMonitorModel {
        UsageMonitorModel(
            providers: [provider],
            settingsStore: InMemorySettingsStore(),
            sleeper: sleeper,
            now: { clock.now },
            wakeSource: wake
        )
    }

    @Test func wakeTriggersOneRefreshPerThreshold() async {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let wake = FakeWakeSource()
        let clock = MutableClock(start)
        let model = makeModel(provider: provider, wake: wake, clock: clock)

        model.start()
        await model.loopTask?.value
        #expect(provider.fetches.total == 1)

        wake.wake()
        await waitUntil { provider.fetches.total == 2 }
        #expect(provider.fetches.total == 2)

        wake.wake()
        await waitUntil { provider.fetches.total == 3 }
        #expect(provider.fetches.total == 2, "second wake inside the threshold is ignored")

        clock.advance(by: 31)
        wake.wake()
        await waitUntil { provider.fetches.total == 3 }
        #expect(provider.fetches.total == 3)
        model.stop()
    }

    @Test func stopReleasesTheWakeSubscription() async {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let wake = FakeWakeSource()
        let model = makeModel(provider: provider, wake: wake, clock: MutableClock(start))

        model.start()
        #expect(model.wakeTask != nil)
        model.start()
        model.stop()
        #expect(model.wakeTask == nil)
        await waitUntil { wake.isTerminated }
        #expect(wake.isTerminated)
    }

    @Test func modelWithoutWakeSourceHasNoWakeTask() {
        let provider = ScriptedProvider(id: .claude, result: .success(.sample(provider: .claude)))
        let model = UsageMonitorModel(
            providers: [provider], settingsStore: InMemorySettingsStore(), sleeper: RecordingSleeper()
        )
        model.start()
        #expect(model.wakeTask == nil)
        model.stop()
    }
}
