import Foundation

/// ChatGPT / Codex subscription usage via the Codex CLI's stored login (ADR 0002, ADR 0003).
public struct OpenAIUsageProvider: UsageProvider {
    public let id: ProviderID = .openAI

    private let credentials: any CredentialSource<OpenAICredential>
    private let client: OpenAIUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<OpenAICredential>,
        client: OpenAIUsageClient,
        now: @escaping @Sendable () -> Date
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
    ) -> OpenAIUsageProvider {
        OpenAIUsageProvider(
            credentials: CachedCredentialSource(
                CodexAuthFileCredentialSource(environment: environment, fileSystem: fileSystem),
                label: ProviderID.openAI.rawValue,
                expiry: { _ in nil },
                now: now
            ),
            client: OpenAIUsageClient(http: http),
            now: now
        )
    }

    public func forgetCredentials() {
        credentials.forget()
    }

    public func linkState() async -> LinkState {
        do {
            let credential = try credentials.load()
            return .linked(AccountInfo(
                planName: OpenAIPlan.displayName(credential.planType),
                accountLabel: credential.email,
                origin: id.credentialOrigin
            ))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let response = try await client.fetch(credential)
        let snapshot = try OpenAIUsageMapper.snapshot(from: response.body, credential: credential, now: now())
        let status = response.statusCode
        let windowCount = snapshot.windows.count
        // swiftlint:disable:next line_length
        UsageLog.providers.info("openai usage fetched status=\(status, privacy: .public) windows=\(windowCount, privacy: .public)")
        return snapshot
    }
}
