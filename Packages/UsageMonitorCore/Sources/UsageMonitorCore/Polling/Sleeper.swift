import Foundation

/// Injected so the poll loop is deterministic under test.
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

/// `ContinuousClock` keeps counting through system sleep, so the first poll after wake fires
/// promptly; the tolerance lets macOS coalesce the wake-up with other timers.
public struct ContinuousClockSleeper: Sleeper {
    public let tolerance: Duration

    public init(tolerance: Duration = .seconds(10)) {
        self.tolerance = tolerance
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, tolerance: tolerance, clock: .continuous)
    }
}
