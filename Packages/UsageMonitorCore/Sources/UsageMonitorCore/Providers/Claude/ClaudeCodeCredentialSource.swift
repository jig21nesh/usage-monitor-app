import Foundation

/// Reads the login Claude Code already holds (ADR 0002): the keychain item first, then the
/// `CLAUDE_CODE_OAUTH_TOKEN` environment variable. There is deliberately no file fallback:
/// Claude Code removes `~/.claude/.credentials.json` on macOS once the keychain item exists, and
/// the sandbox (ADR 0004) has no read exception for it.
public struct ClaudeCodeCredentialSource: CredentialSource {
    public static let keychainService = "Claude Code-credentials"
    public static let tokenEnvironmentVariable = "CLAUDE_CODE_OAUTH_TOKEN"
    /// A real item is well under 1 KB; anything larger is not Claude Code's item.
    static let maxItemBytes = 65_536

    private let keychain: any KeychainReader
    private let environment: UserEnvironment
    private let now: @Sendable () -> Date

    public init(keychain: any KeychainReader, environment: UserEnvironment, now: @escaping @Sendable () -> Date) {
        self.keychain = keychain
        self.environment = environment
        self.now = now
    }

    public func load() throws(ProviderError) -> ClaudeCredential {
        if let credential = try loadFromKeychain() {
            return credential
        }
        if let token = environmentToken() {
            return ClaudeCredential(
                accessToken: token, subscriptionType: nil, rateLimitTier: nil, expiresAt: nil, scopes: []
            )
        }
        throw .credentialsNotFound
    }

    private func loadFromKeychain() throws(ProviderError) -> ClaudeCredential? {
        let data: Data?
        do {
            data = try keychain.genericPassword(service: Self.keychainService, account: nil)
        } catch {
            throw .credentialsUnreadable(Self.reason(for: error))
        }
        guard let data else { return nil }
        guard data.count <= Self.maxItemBytes else { throw .credentialsMalformed("claude_json_too_large") }

        let item: KeychainItem
        do {
            item = try JSONDecoder().decode(KeychainItem.self, from: data)
        } catch {
            throw .credentialsMalformed("claude_json")
        }
        // After Claude Code's own session lapses the item can hold only `mcpOAuth`; treat that as
        // "not logged in" so the user is told to run `claude login`.
        guard let oauth = item.claudeAiOauth,
              let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }

        let expiresAt = VendorDates.epoch(oauth.expiresAt)
        if let expiresAt, expiresAt <= now() {
            throw .credentialsExpired
        }
        return ClaudeCredential(
            accessToken: token,
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier,
            expiresAt: expiresAt,
            scopes: oauth.scopes ?? []
        )
    }

    private func environmentToken() -> String? {
        let raw = environment.variables[Self.tokenEnvironmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static func reason(for error: KeychainReadError) -> String {
        switch error {
        case .interactionRequired: "keychain_interaction_required"
        case .accessDenied: "keychain_access_denied"
        case .unexpectedStatus: "keychain_unexpected_status"
        }
    }

    private struct KeychainItem: Decodable {
        let claudeAiOauth: OAuthSection?
    }

    private struct OAuthSection: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let scopes: [String]?
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}
