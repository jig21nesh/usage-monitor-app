import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ContinuousClockSleeper")
struct SleeperTests {
    @Test func sleepsForAtLeastTheRequestedDuration() async throws {
        let sleeper = ContinuousClockSleeper(tolerance: .zero)
        let clock = ContinuousClock()
        let started = clock.now
        try await sleeper.sleep(for: .milliseconds(20))
        #expect(clock.now - started >= .milliseconds(20))
        #expect(sleeper.tolerance == .zero)
    }

    @Test func defaultToleranceAllowsTimerCoalescing() {
        #expect(ContinuousClockSleeper().tolerance == .seconds(10))
    }

    @Test func cancelledTaskStopsSleeping() async {
        let task = Task {
            try await ContinuousClockSleeper().sleep(for: .seconds(60))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
