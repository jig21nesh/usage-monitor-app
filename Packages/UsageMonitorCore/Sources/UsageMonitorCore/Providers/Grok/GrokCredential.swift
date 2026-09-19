import Foundation

/// The Grok Build CLI login, held in memory for one request (ADR 0002).
public struct GrokCredential: Sendable, Hashable {
    public let accessToken: String
    public let userID: String?
    /// Display only. Never logged.
    public let email: String?
    public let expiresAt: Date?

    public init(accessToken: String, userID: String?, email: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.userID = userID
        self.email = email
        self.expiresAt = expiresAt
    }
}

extension GrokCredential: CustomStringConvertible, CustomDebugStringConvertible {
    /// Defence in depth: an accidental interpolation prints nothing useful to an attacker.
    public var description: String { "GrokCredential(redacted)" }
    public var debugDescription: String { description }
}
