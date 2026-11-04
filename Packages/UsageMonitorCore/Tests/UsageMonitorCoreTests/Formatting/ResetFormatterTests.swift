import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ResetFormatter")
struct ResetFormatterTests {
    let timeZone = TimeZone(identifier: "Australia/Sydney")!

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var us: ResetFormatter {
        ResetFormatter(calendar: calendar, timeZone: timeZone, locale: Locale(identifier: "en_US"))
    }

    var gb: ResetFormatter {
        ResetFormatter(calendar: calendar, timeZone: timeZone, locale: Locale(identifier: "en_GB"))
    }

    /// Saturday 19 September 2026, 09:08 in Sydney.
    var now: Date { date(2026, 9, 19, 9, 8) }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components)!
    }

    @Test func unknownAndPastResets() {
        #expect(us.resetText(for: nil, now: now) == "Reset time unknown")
        #expect(us.resetText(for: now, now: now) == "Resets soon")
        #expect(us.resetText(for: now.addingTimeInterval(-1), now: now) == "Resets soon")
    }

    static let countdownCases: [(TimeInterval, String)] = [
        (59, "Resets in 1 min"),
        (60, "Resets in 1 min"),
        (119, "Resets in 1 min"),
        (2_100, "Resets in 35 min"),
        (17_400, "Resets in 4 hr 50 min"),
        (17_459, "Resets in 4 hr 50 min"),
        (7_200, "Resets in 2 hr"),
        (86_399, "Resets in 23 hr 59 min"),
    ]

    @Test(arguments: countdownCases)
    func countdownWithinADay(offset: TimeInterval, expected: String) {
        #expect(us.resetText(for: now.addingTimeInterval(offset), now: now) == expected)
        #expect(gb.resetText(for: now.addingTimeInterval(offset), now: now) == expected)
    }

    @Test func weekdayAndTimeWithinAWeek() {
        let monday = date(2026, 9, 21, 3, 0)
        #expect(us.resetText(for: monday, now: now) == "Resets Mon 3:00 AM")
        #expect(gb.resetText(for: monday, now: now) == "Resets Mon 03:00")
        let exactlyOneDay = date(2026, 9, 20, 9, 8)
        #expect(exactlyOneDay.timeIntervalSince(now) == ResetFormatter.day)
        #expect(us.resetText(for: exactlyOneDay, now: now) == "Resets Sun 9:08 AM")
        let justUnderAWeek = date(2026, 9, 26, 9, 7, 59)
        #expect(us.resetText(for: justUnderAWeek, now: now) == "Resets Sat 9:07 AM")
    }

    @Test func absoluteDateFromAWeekOnwards() {
        let exactlyAWeek = date(2026, 9, 26, 9, 8)
        #expect(exactlyAWeek.timeIntervalSince(now) == ResetFormatter.week)
        #expect(us.resetText(for: exactlyAWeek, now: now) == "Resets Sep 26, 9:08 AM")
        #expect(gb.resetText(for: exactlyAWeek, now: now) == "Resets 26 Sep, 09:08")
        let nextMonth = date(2026, 10, 20, 4, 41)
        #expect(us.resetText(for: nextMonth, now: now) == "Resets Oct 20, 4:41 AM")
    }

    @Test func percentTextsRoundToWholeNumbers() {
        let window = UsageWindow(id: "w", title: "W", kind: .weekly, usedPercent: 29.4)
        #expect(us.usedText(window) == "29% used")
        #expect(us.remainingText(window) == "71% left")
        let half = UsageWindow(id: "h", title: "H", kind: .session, usedPercent: 42.5)
        #expect(us.percentText(half, style: .used) == "43% used")
        #expect(us.percentText(half, style: .remaining) == "58% left")
        let full = UsageWindow(id: "f", title: "F", kind: .session, usedPercent: 100)
        #expect(us.remainingText(full) == "0% left")
    }

    @Test func defaultsFollowTheCurrentEnvironment() {
        let formatter = ResetFormatter()
        #expect(formatter.locale == .autoupdatingCurrent)
        #expect(formatter.timeZone == .autoupdatingCurrent)
        #expect(formatter.calendar == .autoupdatingCurrent)
    }

    @Test func resetDetailsIncludeLongCountdownsAndExactLocalDates() {
        #expect(us.resetCountdown(for: nil, now: now) == "Reset time unknown")
        #expect(us.resetCountdown(for: now, now: now) == "Resets soon")
        #expect(us.resetCountdown(for: now.addingTimeInterval(59), now: now) == "Resets in 1 min")
        #expect(us.resetCountdown(for: now.addingTimeInterval(86_400), now: now) == "Resets in 1 day")
        #expect(us.resetCountdown(for: now.addingTimeInterval(183_600), now: now) == "Resets in 2 days 3 hr")
        #expect(us.resetDateText(for: nil) == nil)
        let exact = us.resetDateText(for: date(2026, 9, 21, 3, 0))!
        #expect(exact.contains("2026"))
        #expect(exact.contains("3:00 AM"))
        #expect(exact.contains("AEST") || exact.contains("GMT+10"))
        #expect(gb.resetDateText(for: date(2026, 9, 21, 3, 0))!.contains("03:00"))
        // Sydney moves forward an hour: countdown uses elapsed time; the exact date uses local time.
        let beforeDST = date(2026, 10, 4, 1, 30)
        let afterDST = beforeDST.addingTimeInterval(3600)
        #expect(us.resetCountdown(for: afterDST, now: beforeDST) == "Resets in 1 hr")
        #expect(us.resetDateText(for: afterDST)!.contains("3:30 AM"))
    }
}
