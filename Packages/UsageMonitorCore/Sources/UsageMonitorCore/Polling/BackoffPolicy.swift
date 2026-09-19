import Foundation

/// Exponential backoff for a provider that keeps failing (ADR 0003). A vendor `Retry-After`
/// can lengthen a step but never shorten it below the schedule.
public struct BackoffPolicy: Sendable, Hashable {
    public let steps: [Duration]
    public let maximum: Duration

    public static let standard = BackoffPolicy(
        steps: [.seconds(180), .seconds(360), .seconds(720), .seconds(900)],
        maximum: .seconds(3600)
    )

    public init(steps: [Duration], maximum: Duration) {
        precondition(!steps.isEmpty, "backoff needs at least one step")
        self.steps = steps
        self.maximum = maximum
    }

    public func delay(afterConsecutiveFailures failures: Int, retryAfter: TimeInterval? = nil) -> Duration {
        guard failures > 0 else { return .zero }
        let step = steps[min(failures, steps.count) - 1]
        guard let retryAfter, retryAfter.isFinite, retryAfter > 0 else { return step }
        return min(max(.seconds(retryAfter), step), maximum)
    }
}

extension Duration {
    public var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    public var milliseconds: Int {
        Int((timeInterval * 1000).rounded())
    }
}
