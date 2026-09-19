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

/// Everything the user can configure. Persisted as JSON in `UserDefaults`; never holds a secret.
public struct AppSettings: Codable, Sendable, Hashable {
    public var enabledProviders: Set<ProviderID>
    public var refreshInterval: RefreshInterval
    public var launchAtLogin: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        enabledProviders: Set<ProviderID>,
        refreshInterval: RefreshInterval,
        launchAtLogin: Bool,
        hasCompletedOnboarding: Bool
    ) {
        self.enabledProviders = enabledProviders
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let `default` = AppSettings(
        enabledProviders: Set(ProviderID.allCases),
        refreshInterval: .default,
        launchAtLogin: false,
        hasCompletedOnboarding: false
    )
}
