import Foundation
import UsageMonitorCore

/// App-side text helpers. Reset and percent wording comes from Core's `ResetFormatter`, so the
/// panel, the diagnostics report and the tests agree on every string.
enum ResetText {
    static let formatter = ResetFormatter()

    static func text(for date: Date?, now: Date = .now) -> String {
        formatter.resetText(for: date, now: now)
    }
}

enum UsageText {
    static func percent(_ window: UsageWindow, style: PercentStyle) -> String {
        ResetText.formatter.percentText(window, style: style)
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
