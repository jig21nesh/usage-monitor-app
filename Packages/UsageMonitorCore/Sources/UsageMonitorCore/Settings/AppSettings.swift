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

/// Percent-used boundaries for the menu bar colour: below `warning` is green, from `warning` up
/// to `critical` is orange, `critical` and above is red (ADR 0008).
public struct MenuBarThresholds: Codable, Sendable, Hashable {
    public var warningPercent: Double
    public var criticalPercent: Double

    public static let `default` = MenuBarThresholds(warningPercent: 60, criticalPercent: 80)

    /// Values are clamped to 0...100 and ordered so warning never exceeds critical.
    public init(warningPercent: Double, criticalPercent: Double) {
        let warning = Self.clamp(warningPercent)
        let critical = Self.clamp(criticalPercent)
        self.warningPercent = min(warning, critical)
        self.criticalPercent = max(warning, critical)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }
}

/// Everything the user can configure. Persisted as JSON in `UserDefaults`; never holds a secret.
public struct AppSettings: Codable, Sendable, Hashable {
    public var enabledProviders: Set<ProviderID>
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool
    public var hasCompletedOnboarding: Bool
    public var percentStyle: PercentStyle
    /// Provider whose session limit drives the menu bar colour; nil means automatic (ADR 0008).
    public var menuBarProvider: ProviderID?
    public var menuBarThresholds: MenuBarThresholds
    public var colorsMenuBarIcon: Bool

    public init(
        enabledProviders: Set<ProviderID>,
        refreshInterval: RefreshInterval,
        launchAtLogin: Bool,
        hasCompletedOnboarding: Bool,
        percentStyle: PercentStyle = .used,
        menuBarProvider: ProviderID? = nil,
        menuBarThresholds: MenuBarThresholds = .default,
        colorsMenuBarIcon: Bool = true
    ) {
        self.enabledProviders = enabledProviders
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.percentStyle = percentStyle
        self.menuBarProvider = menuBarProvider
        self.menuBarThresholds = menuBarThresholds
        self.colorsMenuBarIcon = colorsMenuBarIcon
    }

    /// Keys added after the first release decode to their defaults, so older settings still load.
    /// An unknown provider raw value inside `enabledProviders` is dropped rather than failing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawProviders = try container.decode([String].self, forKey: .enabledProviders)
        self.init(
            enabledProviders: Set(rawProviders.compactMap(ProviderID.init(rawValue:))),
            refreshInterval: try container.decode(RefreshInterval.self, forKey: .refreshInterval),
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin),
            hasCompletedOnboarding: try container.decode(Bool.self, forKey: .hasCompletedOnboarding),
            percentStyle: try container.decodeIfPresent(PercentStyle.self, forKey: .percentStyle) ?? .used,
            menuBarProvider: try container.decodeIfPresent(ProviderID.self, forKey: .menuBarProvider),
            menuBarThresholds: try container.decodeIfPresent(MenuBarThresholds.self, forKey: .menuBarThresholds)
                ?? .default,
            colorsMenuBarIcon: try container.decodeIfPresent(Bool.self, forKey: .colorsMenuBarIcon) ?? true
        )
    }

    public static let `default` = AppSettings(
        enabledProviders: Set(ProviderID.defaultEnabled),
        refreshInterval: .default,
        launchAtLogin: false,
        hasCompletedOnboarding: false
    )
}
