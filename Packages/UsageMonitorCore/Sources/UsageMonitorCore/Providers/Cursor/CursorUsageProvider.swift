import Foundation

/// Cursor plan usage via the login Cursor.app or the `cursor-agent` CLI already stores (ADR 0008).
public struct CursorUsageProvider: UsageProvider {
    public let id: ProviderID = .cursor

    private let credentials: any CredentialSource<CursorCredential>
    private let client: CursorUsageClient
    private let now: @Sendable () -> Date

    public init(
        credentials: any CredentialSource<CursorCredential>,
        client: CursorUsageClient,
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
    ) -> CursorUsageProvider {
        CursorUsageProvider(
            credentials: CursorCredentialSource(
                environment: environment,
                database: SystemSQLiteKeyValueReader(),
                keychain: keychain,
                fileSystem: fileSystem,
                now: now
            ),
            client: CursorUsageClient(http: http),
            now: now
        )
    }

    public func linkState() async -> LinkState {
        do {
            let credential = try credentials.load()
            return .linked(AccountInfo(
                planName: credential.planName,
                accountLabel: credential.email,
                origin: id.credentialOrigin
            ))
        } catch {
            return .notLinked(error)
        }
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let credential = try credentials.load()
        let response = try await client.fetchCurrentPeriodUsage(token: credential.accessToken)
        let snapshot = try CursorUsageMapper.snapshot(from: response.body, credential: credential, now: now())
        let status = response.statusCode
        let windowCount = snapshot.windows.count
        // swiftlint:disable:next line_length
        UsageLog.providers.info("cursor usage fetched status=\(status, privacy: .public) windows=\(windowCount, privacy: .public)")
        return snapshot
    }
}
