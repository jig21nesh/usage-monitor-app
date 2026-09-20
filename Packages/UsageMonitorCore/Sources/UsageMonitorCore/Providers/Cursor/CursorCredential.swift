import Foundation

/// The subset of Cursor's stored login the app needs. The refresh token stored beside it is
/// never read (ADR 0002). Printing an instance never reveals the access token.
public struct CursorCredential: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    /// JWT subject with Cursor's `auth0|` prefix removed; the dashboard cookie form needs it bare.
    public let subject: String?
    public let expiresAt: Date?
    /// Display only, from Cursor's cached email; never logged.
    public let email: String?
    /// Cursor's stored membership type, e.g. "pro", "free", "ultra".
    public let membershipType: String?

    public init(accessToken: String, subject: String?, expiresAt: Date?, email: String?, membershipType: String?) {
        self.accessToken = accessToken
        self.subject = subject
        self.expiresAt = expiresAt
        self.email = email
        self.membershipType = membershipType
    }

    /// "Pro", "Ultra", "Free" or nil when unknown.
    public var planName: String? {
        guard let raw = membershipType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        switch raw {
        case "pro": return "Pro"
        case "pro_plus", "pro-plus", "proplus": return "Pro+"
        case "ultra": return "Ultra"
        case "free": return "Free"
        case "free_trial", "free-trial": return "Free trial"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    public var description: String {
        let expiry = expiresAt.map(String.init(describing:)) ?? "none"
        return "CursorCredential(plan: \(planName ?? "unknown"), expiresAt: \(expiry), accessToken: <redacted>)"
    }

    public var debugDescription: String { description }
}
