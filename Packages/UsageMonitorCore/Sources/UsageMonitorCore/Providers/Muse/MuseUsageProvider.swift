import Foundation

/// Meta Muse Code subscription usage: the CLI's stored login + the key endpoint + a pure mapper
/// (ADR 0002, ADR 0003, ADR 0008). Experimental until a live subscription confirms polling tolerance.
public struct MuseUsageProvider: UsageProvider {
    public let id: ProviderID = .muse

    /// Nobody has verified that Meta's key endpoint tolerates frequent polling, and it returns a
    /// credential on every call, so it is hit at most every 15 minutes regardless of the user's
    /// refresh interval or a forced refresh (ADR 0003 amendment).
    public static let pollFloor: Duration = .seconds(900)

    private let credentials: any CredentialSource<MuseCredential>
    private let client: MuseUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<MuseCredential>,
        client: MuseUsageClient,
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
    ) -> MuseUsageProvider {
        MuseUsageProvider(
            credentials: MuseCredentialSource(environment: environment, fileSystem: fileSystem, keychain: keychain),
            client: MuseUsageClient(http: http),
            now: now
        )
    }

    public var minimumPollInterval: Duration? { Self.pollFloor }

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
        let body = try await client.fetchUsage(token: credential.accessToken)
        let snapshot = try MuseUsageMapper.snapshot(from: body, fetchedAt: now())
        let windowCount = snapshot.windows.count
        UsageLog.providers.info("muse usage fetched windows=\(windowCount, privacy: .public)")
        return snapshot
    }
}
