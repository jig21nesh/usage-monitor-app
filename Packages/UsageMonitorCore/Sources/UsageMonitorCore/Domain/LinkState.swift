import Foundation

/// What the app knows about the linked account without revealing anything secret.
public struct AccountInfo: Sendable, Hashable, Codable {
    public let planName: String?
    /// A non-secret label such as an email or a plan tier. Never a token fragment.
    public let accountLabel: String?
    public let origin: String

    public init(planName: String?, accountLabel: String?, origin: String) {
        self.planName = planName
        self.accountLabel = accountLabel
        self.origin = origin
    }
}

public enum LinkState: Sendable, Hashable {
    case unknown
    case linked(AccountInfo)
    case notLinked(ProviderError)

    public var account: AccountInfo? {
        if case .linked(let account) = self { return account }
        return nil
    }

    public var isLinked: Bool { account != nil }
}
