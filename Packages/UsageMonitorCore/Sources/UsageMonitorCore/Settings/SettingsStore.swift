import Foundation

public protocol SettingsStore: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// `UserDefaults` is documented as thread-safe, hence the unchecked conformance.
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let key = "com.curiouspilabs.UsageMonitor.settings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Corrupt or outdated data falls back to defaults rather than crashing or half-applying.
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            UsageLog.settings.error("settings decode failed; using defaults")
            return .default
        }
    }

    public func save(_ settings: AppSettings) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            UsageLog.settings.error("settings encode failed; change not persisted")
        }
    }
}
