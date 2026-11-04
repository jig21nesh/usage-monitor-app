import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("Usage summaries")
struct UsageSummaryFormatterTests {
    let now = Date(timeIntervalSince1970: 1_793_750_400)

    private func status(percent: Double = 42.4, stale: Bool = false, reset: Date? = nil) -> MenuBarStatus {
        MenuBarStatus(
            provider: .openAI,
            window: UsageWindow(
                id: "s", title: "Current session", kind: .session, usedPercent: percent, resetsAt: reset
            ),
            level: .ok, isStale: stale
        )
    }

    @Test func percentageFollowsPreferenceAndMarksStaleReadings() {
        #expect(UsageSummaryFormatter.menuBarPercentage(for: status(), style: .used) == "42%")
        #expect(UsageSummaryFormatter.menuBarPercentage(for: status(), style: .remaining) == "58%")
        #expect(UsageSummaryFormatter.menuBarPercentage(for: status(percent: 100), style: .remaining) == "0%")
        #expect(UsageSummaryFormatter.menuBarPercentage(for: status(percent: 0), style: .used) == "0%")
        #expect(UsageSummaryFormatter.menuBarPercentage(for: status(stale: true), style: .used) == "42%*")
        #expect(UsageSummaryFormatter.menuBarPercentage(for: .unknown, style: .remaining) == "—")
    }

    @Test func tooltipIncludesTrackedWindowAndResetDetails() {
        let formatter = ResetFormatter(timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_GB"))
        let summary = UsageSummaryFormatter.menuBarSummary(
            for: status(stale: true, reset: now.addingTimeInterval(7_800)),
            style: .remaining, now: now, formatter: formatter
        )
        #expect(summary.hasPrefix("OpenAI session 58% left"))
        #expect(summary.contains("Stale — last known usage"))
        #expect(summary.contains("Resets in 2 hr 10 min"))
        #expect(summary.contains("2026"))
        #expect(UsageSummaryFormatter.menuBarSummary(for: .unknown, style: .used, now: now) == "Usage unknown")
        let unknownReset = UsageSummaryFormatter.menuBarSummary(for: status(), style: .used, now: now)
        #expect(unknownReset.contains("Reset time unknown"))
        #expect(!unknownReset.contains("Stale"))
        let monthly = MenuBarStatus(
            provider: .copilot,
            window: UsageWindow(id: "m", title: "Premium requests", kind: .monthly, usedPercent: 40),
            level: .ok, isStale: false
        )
        #expect(UsageSummaryFormatter.menuBarSummary(for: monthly, style: .used, now: now)
            .hasPrefix("GitHub Copilot premium requests 40% used"))
    }

    @Test func resetCountDistinguishesUnknownZeroAndStale() {
        #expect(UsageSummaryFormatter.availableResets(nil, isStale: false) == "Available resets: not reported")
        #expect(UsageSummaryFormatter.availableResets(-1, isStale: false) == "Available resets: not reported")
        #expect(UsageSummaryFormatter.availableResets(0, isStale: false) == "0 resets available")
        #expect(UsageSummaryFormatter.availableResets(1, isStale: false) == "1 reset available")
        #expect(UsageSummaryFormatter.availableResets(3, isStale: true) == "3 resets available (last known)")
    }
}
