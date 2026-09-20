import Foundation

/// OpenCode Go plan usage via the OpenCode CLI's stored key (ADR 0002, ADR 0008).
public struct OpenCodeGoUsageProvider: UsageProvider {
    public let id: ProviderID = .opencodeGo

    private let credentials: any CredentialSource<OpenCodeCredential>
    private let client: OpenCodeGoUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<OpenCodeCredential>,
        client: OpenCodeGoUsageClient,
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
    ) -> OpenCodeGoUsageProvider {
        OpenCodeGoUsageProvider(
            credentials: OpenCodeCredentialSource(fileSystem: fileSystem, environment: environment),
            client: OpenCodeGoUsageClient(http: http),
            now: now
        )
    }

    public func linkState() async -> LinkState {
        do {
            _ = try credentials.load()
            return .linked(AccountInfo(
                planName: OpenCodeGoUsageMapper.planName,
                accountLabel: nil,
                origin: id.credentialOrigin
            ))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let response = try await client.fetch(credential)
        let snapshot = try OpenCodeGoUsageMapper.snapshot(from: response.body, fetchedAt: now())
        let status = response.statusCode
        let windowCount = snapshot.windows.count
        // swiftlint:disable:next line_length
        UsageLog.providers.info("opencode usage fetched status=\(status, privacy: .public) windows=\(windowCount, privacy: .public)")
        return snapshot
    }
}
