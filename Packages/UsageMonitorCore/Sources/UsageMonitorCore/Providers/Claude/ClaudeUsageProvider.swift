import Foundation

/// Claude subscription usage: Claude Code's stored login + the OAuth usage endpoint + a pure mapper.
public struct ClaudeUsageProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let credentials: any CredentialSource<ClaudeCredential>
    private let client: ClaudeUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<ClaudeCredential>,
        client: ClaudeUsageClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.client = client
        self.now = now
    }

    public static func live(
        environment: UserEnvironment,
        http: any HTTPClient,
        keychain: any KeychainReader,
        fileSystem: any FileSystem,
        now: @escaping @Sendable () -> Date
    ) -> ClaudeUsageProvider {
        ClaudeUsageProvider(
            credentials: CachedCredentialSource(
                ClaudeCodeCredentialSource(keychain: keychain, environment: environment, now: now),
                label: ProviderID.claude.rawValue,
                expiry: { $0.expiresAt },
                now: now
            ),
            client: ClaudeUsageClient(http: http),
            now: now
        )
    }

    public func forgetCredentials() {
        credentials.forget()
    }

    public func linkState() async -> LinkState {
        do {
            let credential = try credentials.load()
            return .linked(AccountInfo(planName: credential.planName, accountLabel: nil, origin: id.credentialOrigin))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let response = try await client.fetchUsage(token: credential.accessToken)
        let bytes = response.body.count
        UsageLog.providers.info(
            "claude usage fetched status=\(response.statusCode, privacy: .public) bytes=\(bytes, privacy: .public)"
        )
        return try ClaudeUsageMapper.snapshot(from: response.body, planName: credential.planName, fetchedAt: now())
    }
}
