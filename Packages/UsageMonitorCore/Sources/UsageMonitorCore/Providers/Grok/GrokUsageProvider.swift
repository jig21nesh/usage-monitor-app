import Foundation

/// Grok adapter: Grok Build CLI credential, one billing request, pure mapper (ADR 0001).
public struct GrokUsageProvider: UsageProvider {
    public let id: ProviderID = .grok

    let credentials: any CredentialSource<GrokCredential>
    let client: GrokUsageClient
    let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<GrokCredential>,
        client: GrokUsageClient,
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
    ) -> GrokUsageProvider {
        GrokUsageProvider(
            credentials: GrokBuildCredentialSource(environment: environment, fileSystem: fileSystem, now: now),
            client: GrokUsageClient(http: http),
            now: now
        )
    }

    public func linkState() async -> LinkState {
        do {
            let credential = try credentials.load()
            return .linked(AccountInfo(planName: nil, accountLabel: credential.email, origin: id.credentialOrigin))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let body: Data
        do {
            body = try await client.fetchBilling(with: credential)
        } catch {
            UsageLog.providers.error("grok fetch failed error=\(error.logIdentifier, privacy: .public)")
            throw error
        }
        let snapshot = try GrokUsageMapper.snapshot(from: body, fetchedAt: now())
        UsageLog.providers.info("grok fetch ok windows=\(snapshot.windows.count, privacy: .public)")
        return snapshot
    }
}
