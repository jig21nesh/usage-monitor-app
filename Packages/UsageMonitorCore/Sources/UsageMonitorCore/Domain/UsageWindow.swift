import Foundation

public enum UsageWindowKind: String, Codable, Sendable, Hashable {
    /// Rolling short window, e.g. Claude's and Codex's 5-hour session.
    case session
    /// Rolling 7-day window across all models.
    case weekly
    /// Rolling 7-day window scoped to one model, e.g. Claude's per-model weekly row.
    case weeklyModel
    case monthly
    case other
}

/// One utilisation bar in the UI. `usedPercent` is always within 0...100.
public struct UsageWindow: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let kind: UsageWindowKind
    public let usedPercent: Double
    public let resetsAt: Date?
    public let windowDuration: TimeInterval?

    public init(
        id: String,
        title: String,
        kind: UsageWindowKind,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.usedPercent = Self.clampedPercent(usedPercent)
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            kind: try container.decode(UsageWindowKind.self, forKey: .kind),
            usedPercent: try container.decode(Double.self, forKey: .usedPercent),
            resetsAt: try container.decodeIfPresent(Date.self, forKey: .resetsAt),
            windowDuration: try container.decodeIfPresent(TimeInterval.self, forKey: .windowDuration)
        )
    }

    public var remainingPercent: Double { 100 - usedPercent }

    /// Vendors have shipped fractions, percents and out-of-range values; the UI must never see anything outside 0...100.
    static func clampedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }
}
