import Foundation

/// GitHub Copilot quota via the GitHub CLI's stored login (ADR 0002, ADR 0008).
public struct CopilotUsageProvider: UsageProvider {
    public let id: ProviderID = .copilot

    private let credentials: any CredentialSource<CopilotCredential>
    private let client: CopilotUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<CopilotCredential>,
        client: CopilotUsageClient,
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
    ) -> CopilotUsageProvider {
        CopilotUsageProvider(
            credentials: CopilotCredentialSource(keychain: keychain, fileSystem: fileSystem, environment: environment),
            client: CopilotUsageClient(http: http),
            now: now
        )
    }

    public func linkState() async -> LinkState {
        do {
            let credential = try credentials.load()
            return .linked(AccountInfo(planName: nil, accountLabel: credential.login, origin: credential.source))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let response = try await client.fetch(credential)
        let snapshot = try CopilotUsageMapper.snapshot(from: response.body, login: credential.login, fetchedAt: now())
        let status = response.statusCode
        let windowCount = snapshot.windows.count
        // swiftlint:disable:next line_length
        UsageLog.providers.info("copilot usage fetched status=\(status, privacy: .public) windows=\(windowCount, privacy: .public)")
        return snapshot
    }
}
