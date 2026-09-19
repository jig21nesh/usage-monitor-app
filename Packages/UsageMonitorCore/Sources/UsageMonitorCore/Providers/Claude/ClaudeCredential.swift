import Foundation

/// The subset of Claude Code's stored login the app needs. The refresh token is never read
/// (ADR 0002). Printing an instance never reveals the access token.
public struct ClaudeCredential: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let subscriptionType: String?
    public let rateLimitTier: String?
    public let expiresAt: Date?
    public let scopes: [String]

    public init(
        accessToken: String,
        subscriptionType: String?,
        rateLimitTier: String?,
        expiresAt: Date?,
        scopes: [String]
    ) {
        self.accessToken = accessToken
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    /// Human-readable plan for the UI, e.g. "Max (20x)". Nil when the store carried no plan.
    public var planName: String? {
        guard let raw = subscriptionType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        switch raw {
        case "max":
            let tier = rateLimitTier?.lowercased() ?? ""
            if tier.contains("20x") { return "Max (20x)" }
            if tier.contains("5x") { return "Max (5x)" }
            return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    public var description: String {
        let expiry = expiresAt.map(String.init(describing:)) ?? "none"
        return "ClaudeCredential(plan: \(planName ?? "unknown"), expiresAt: \(expiry), "
            + "scopes: \(scopes.count), accessToken: <redacted>)"
    }

    public var debugDescription: String { description }
}
