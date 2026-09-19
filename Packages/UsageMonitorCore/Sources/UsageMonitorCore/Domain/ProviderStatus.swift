import Foundation

/// The UI-facing state of one provider: link state, last snapshot, last error and retry schedule.
public struct ProviderStatus: Sendable, Hashable, Identifiable {
    public let provider: ProviderID
    public var isEnabled: Bool
    public var link: LinkState
    public var snapshot: UsageSnapshot?
    public var lastError: ProviderError?
    public var lastSuccess: Date?
    public var isRefreshing: Bool
    public var nextRetryAt: Date?

    public init(
        provider: ProviderID,
        isEnabled: Bool,
        link: LinkState = .unknown,
        snapshot: UsageSnapshot? = nil,
        lastError: ProviderError? = nil,
        lastSuccess: Date? = nil,
        isRefreshing: Bool = false,
        nextRetryAt: Date? = nil
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.link = link
        self.snapshot = snapshot
        self.lastError = lastError
        self.lastSuccess = lastSuccess
        self.isRefreshing = isRefreshing
        self.nextRetryAt = nextRetryAt
    }

    public var id: ProviderID { provider }

    /// A snapshot is shown but the most recent poll failed, so the numbers may be out of date.
    public var isStale: Bool { snapshot != nil && lastError != nil }
}
