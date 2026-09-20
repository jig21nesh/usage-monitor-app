import Foundation

public enum MenuBarLevel: String, Sendable, Hashable, Codable {
    case ok
    case warning
    case critical
    case unknown
}

/// What the menu bar icon reflects: one provider's session limit, coloured by threshold (ADR 0008).
public struct MenuBarStatus: Sendable, Hashable {
    public let provider: ProviderID?
    public let window: UsageWindow?
    public let level: MenuBarLevel
    public let isStale: Bool

    public init(provider: ProviderID?, window: UsageWindow?, level: MenuBarLevel, isStale: Bool) {
        self.provider = provider
        self.window = window
        self.level = level
        self.isStale = isStale
    }

    public static let unknown = MenuBarStatus(provider: nil, window: nil, level: .unknown, isStale: false)
}

public enum MenuBarStatusResolver {
    public static func level(forPercent percent: Double?, thresholds: MenuBarThresholds) -> MenuBarLevel {
        guard let percent, percent.isFinite else { return .unknown }
        if percent >= thresholds.criticalPercent { return .critical }
        if percent >= thresholds.warningPercent { return .warning }
        return .ok
    }

    /// "The session limit": the session window when the vendor has one, otherwise the fullest window.
    public static func trackedWindow(in snapshot: UsageSnapshot) -> UsageWindow? {
        snapshot.windows.first { $0.kind == .session } ?? snapshot.mostUsedWindow
    }

    /// Chosen provider first; a single enabled provider next; otherwise the enabled provider whose
    /// tracked window is fullest, so the icon never hides the worst case.
    public static func resolve(statuses: [ProviderStatus], settings: AppSettings) -> MenuBarStatus {
        let enabled = statuses.filter(\.isEnabled)
        let candidate: ProviderStatus?
        if let chosen = settings.menuBarProvider, let status = enabled.first(where: { $0.provider == chosen }) {
            candidate = status
        } else if enabled.count == 1 {
            candidate = enabled.first
        } else {
            candidate = enabled
                .compactMap { status in status.snapshot.flatMap(trackedWindow).map { (status, $0.usedPercent) } }
                .max { $0.1 < $1.1 }?.0
        }
        guard let candidate else { return .unknown }
        let window = candidate.snapshot.flatMap(trackedWindow)
        return MenuBarStatus(
            provider: candidate.provider,
            window: window,
            level: level(forPercent: window?.usedPercent, thresholds: settings.menuBarThresholds),
            isStale: candidate.isStale
        )
    }
}
