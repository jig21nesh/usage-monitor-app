import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("BackoffPolicy")
struct BackoffPolicyTests {
    let policy = BackoffPolicy.standard

    @Test func noFailuresMeansNoDelay() {
        #expect(policy.delay(afterConsecutiveFailures: 0) == .zero)
        #expect(policy.delay(afterConsecutiveFailures: -3) == .zero)
    }

    @Test(arguments: [(1, 180), (2, 360), (3, 720), (4, 900), (5, 900), (50, 900)])
    func escalatesThenSaturates(failures: Int, seconds: Int) {
        #expect(policy.delay(afterConsecutiveFailures: failures) == .seconds(seconds))
    }

    @Test func retryAfterLengthensButNeverShortens() {
        #expect(policy.delay(afterConsecutiveFailures: 1, retryAfter: 30) == .seconds(180))
        #expect(policy.delay(afterConsecutiveFailures: 1, retryAfter: 600) == .seconds(600))
    }

    @Test func retryAfterIsCappedAtMaximum() {
        #expect(policy.delay(afterConsecutiveFailures: 1, retryAfter: 86_400) == .seconds(3600))
    }

    @Test(arguments: [0.0, -5.0, Double.nan, Double.infinity])
    func invalidRetryAfterIsIgnored(value: Double) {
        #expect(policy.delay(afterConsecutiveFailures: 1, retryAfter: value) == .seconds(180))
    }

    @Test func durationHelpers() {
        #expect(Duration.seconds(1.5).timeInterval == 1.5)
        #expect(Duration.seconds(1.5).milliseconds == 1500)
        #expect(Duration.seconds(180).milliseconds == 180_000)
    }
}
