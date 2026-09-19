import Foundation
import UsageMonitorCore

// TEMPORARY: the polling branch adds `ResetFormatter` to UsageMonitorCore. The integrator swaps
// the body of `ResetText.text` for that formatter; this is the only App file that formats resets.
enum ResetText {
    static func text(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "Reset time unknown" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Resets soon" }
        if remaining < 24 * 3600 {
            return "Resets in " + countdown(minutes: Int((remaining / 60).rounded()))
        }
        if remaining < 7 * 24 * 3600 {
            return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return "Resets " + date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private static func countdown(minutes total: Int) -> String {
        let hours = total / 60
        let minutes = total % 60
        switch (hours, minutes) {
        case (0, _): return "\(max(minutes, 1)) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(minutes) min"
        }
    }
}

enum UsageText {
    static func used(_ percent: Double) -> String {
        "\(Int(percent.rounded()))% used"
    }

    static func lastUpdated(_ date: Date?) -> String {
        guard let date else { return "Not refreshed yet" }
        return "Updated " + date.formatted(.dateTime.hour().minute())
    }

    static func nextRefresh(after date: Date?, interval: RefreshInterval, isRefreshing: Bool) -> String {
        if isRefreshing { return "Refreshing now" }
        guard let date else { return "Waiting for first refresh" }
        let next = date.addingTimeInterval(TimeInterval(interval.rawValue))
        return "Next at " + next.formatted(.dateTime.hour().minute())
    }
}

extension ProviderID {
    var symbolName: String {
        switch self {
        case .claude: "sparkles"
        case .openAI: "brain.head.profile"
        case .grok: "bolt"
        }
    }
}
