import Foundation

/// Produces the reset and percent strings the usage panel shows. Pure: every input that varies
/// by machine (calendar, time zone, locale, "now") is injected so the output is testable.
public struct ResetFormatter: Sendable {
    public var calendar: Calendar
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.timeZone = timeZone
        self.locale = locale
    }

    static let day: TimeInterval = 86_400
    static let week: TimeInterval = 7 * 86_400

    /// "Resets in 4 hr 50 min" inside a day, "Resets Mon 3:00 AM" inside a week, otherwise
    /// "Resets Sep 20, 4:41 AM". Mirrors the wording of the vendors' own usage pages.
    public func resetText(for date: Date?, now: Date) -> String {
        guard let date else { return "Reset time unknown" }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "Resets soon" }
        if remaining < Self.day {
            return "Resets in \(Self.countdown(remaining))"
        }
        if remaining < Self.week {
            return Self.plainSpaces("Resets \(date.formatted(style.weekday(.abbreviated).hour().minute()))")
        }
        let day = date.formatted(style.month(.abbreviated).day())
        let time = date.formatted(style.hour().minute())
        return Self.plainSpaces("Resets \(day), \(time)")
    }

    public func usedText(_ window: UsageWindow) -> String {
        "\(Self.wholePercent(window.usedPercent))% used"
    }

    public func remainingText(_ window: UsageWindow) -> String {
        "\(Self.wholePercent(window.remainingPercent))% left"
    }

    public func percentText(_ window: UsageWindow, style: PercentStyle) -> String {
        switch style {
        case .used: usedText(window)
        case .remaining: remainingText(window)
        }
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }

    /// Whole minutes, rounded down, never below one minute so the bar never says "in 0 min".
    static func countdown(_ remaining: TimeInterval) -> String {
        let totalMinutes = max(1, Int(remaining / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        return parts.joined(separator: " ")
    }

    /// ICU separates "3:00" and "AM" with a narrow no-break space; the panel and the diagnostics
    /// report want the plain space the vendors' own pages use.
    static func plainSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func wholePercent(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
