import Foundation

/// Everything one successful poll learned about one provider.
public struct UsageSnapshot: Codable, Sendable, Hashable {
    public let provider: ProviderID
    public let planName: String?
    public let windows: [UsageWindow]
    public let fetchedAt: Date

    public init(provider: ProviderID, planName: String?, windows: [UsageWindow], fetchedAt: Date) {
        self.provider = provider
        self.planName = planName
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var mostUsedWindow: UsageWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }
}
