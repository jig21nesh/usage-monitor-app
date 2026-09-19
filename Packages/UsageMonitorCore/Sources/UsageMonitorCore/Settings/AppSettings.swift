import Foundation

public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900

    public static let `default` = RefreshInterval.twoMinutes

    public var id: Int { rawValue }
    public var duration: Duration { .seconds(rawValue) }

    public var title: String {
        let minutes = rawValue / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

/// Whether bars read "29% used" (Claude's wording) or "42% left" (OpenAI's wording).
public enum PercentStyle: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case used
    case remaining

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .used: "Percent used"
        case .remaining: "Percent left"
        }
    }
}

/// Everything the user can configure. Persisted as JSON in `UserDefaults`; never holds a secret.
public struct AppSettings: Codable, Sendable, Hashable {
    public var enabledProviders: Set<ProviderID>
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool
    public var hasCompletedOnboarding: Bool
    public var percentStyle: PercentStyle

    public init(
        enabledProviders: Set<ProviderID>,
        refreshInterval: RefreshInterval,
        launchAtLogin: Bool,
        hasCompletedOnboarding: Bool,
        percentStyle: PercentStyle = .used
    ) {
        self.enabledProviders = enabledProviders
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.percentStyle = percentStyle
    }

    /// `percentStyle` was added after the first release, so settings saved without it still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabledProviders: try container.decode(Set<ProviderID>.self, forKey: .enabledProviders),
            refreshInterval: try container.decode(RefreshInterval.self, forKey: .refreshInterval),
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin),
            hasCompletedOnboarding: try container.decode(Bool.self, forKey: .hasCompletedOnboarding),
            percentStyle: try container.decodeIfPresent(PercentStyle.self, forKey: .percentStyle) ?? .used
        )
    }

    public static let `default` = AppSettings(
        enabledProviders: Set(ProviderID.allCases),
        refreshInterval: .default,
        launchAtLogin: false,
        hasCompletedOnboarding: false
    )
}
