import Foundation

/// Everything one successful poll learned about one provider.
public struct UsageSnapshot: Codable, Sendable, Hashable {
    public let provider: ProviderID
    public let planName: String?
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    /// Nil means unreported, not zero. A reset is an entitlement, separate from usage credit balances.
    public let availableResetCount: Int?

    public init(
        provider: ProviderID,
        planName: String?,
        windows: [UsageWindow],
        fetchedAt: Date,
        availableResetCount: Int? = nil
    ) {
        self.provider = provider
        self.planName = planName
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.availableResetCount = availableResetCount.flatMap { $0 >= 0 ? $0 : nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            provider: try container.decode(ProviderID.self, forKey: .provider),
            planName: try container.decodeIfPresent(String.self, forKey: .planName),
            windows: try container.decode([UsageWindow].self, forKey: .windows),
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt),
            availableResetCount: try container.decodeIfPresent(Int.self, forKey: .availableResetCount)
        )
    }

    public var mostUsedWindow: UsageWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }
}
