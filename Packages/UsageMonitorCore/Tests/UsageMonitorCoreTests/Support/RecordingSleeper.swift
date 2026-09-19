import Foundation
import Synchronization
@testable import UsageMonitorCore

/// Records requested sleeps and ends the poll loop by throwing on the Nth call.
final class RecordingSleeper: Sleeper, Sendable {
    private let state = Mutex<[Duration]>([])
    let maxSleeps: Int

    init(maxSleeps: Int = 1) {
        self.maxSleeps = maxSleeps
    }

    var sleeps: [Duration] { state.withLock { $0 } }

    func sleep(for duration: Duration) async throws {
        let count = state.withLock { sleeps -> Int in
            sleeps.append(duration)
            return sleeps.count
        }
        if count >= maxSleeps {
            throw CancellationError()
        }
        await Task.yield()
    }
}
