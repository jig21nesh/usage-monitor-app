import Foundation
import Testing
@testable import UsageMonitorCore

struct StubClaudeCredentials: CredentialSource {
    let result: Result<ClaudeCredential, ProviderError>

    func load() throws(ProviderError) -> ClaudeCredential {
        try result.get()
    }
}

@Suite("ClaudeUsageProvider")
struct ClaudeUsageProviderTests {
    static let secretToken = "sk-ant-oat01-SECRETSECRET"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func credential(token: String = secretToken) -> ClaudeCredential {
        ClaudeCredential(
            accessToken: token, subscriptionType: "max", rateLimitTier: "default_claude_max_20x",
            expiresAt: nil, scopes: ["user:profile"]
        )
    }

    private func makeProvider(
        credentials: Result<ClaudeCredential, ProviderError>,
        http: FakeHTTPClient = FakeHTTPClient(),
        clientVersion: String = ClaudeUsageClient.defaultClientVersion
    ) -> ClaudeUsageProvider {
        let fixedNow = now
        return ClaudeUsageProvider(
            credentials: StubClaudeCredentials(result: credentials),
            client: ClaudeUsageClient(http: http, clientVersion: clientVersion),
            now: { fixedNow }
        )
    }

    private func fixture() throws -> Data {
        try Fixtures.data("oauth-usage-max", subdirectory: "claude")
    }

    @Test func requestUsesTheExactHeadersTheEndpointExpects() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try fixture())
        let provider = makeProvider(credentials: .success(credential(token: "sk-ant-oat01-abc")), http: http)
        _ = try await provider.fetchUsage()

        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url == URL(string: "https://api.anthropic.com/api/oauth/usage"))
        #expect(request.body == nil)
        #expect(request.headers == [
            "Authorization": "Bearer sk-ant-oat01-abc",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
            "User-Agent": "claude-cli/2.1.277 (external, cli)",
        ])
        #expect(http.requests.count == 1)
    }

    @Test func clientVersionIsReflectedInUserAgent() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try fixture())
        _ = try await makeProvider(credentials: .success(credential()), http: http, clientVersion: "9.9.9").fetchUsage()
        #expect(http.requests.first?.headers["User-Agent"] == "claude-cli/9.9.9 (external, cli)")
        #expect(ClaudeUsageClient(http: http).userAgent == "claude-cli/2.1.277 (external, cli)")
    }

    @Test func successMapsSnapshotWithPlanAndFetchTime() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try fixture())
        let snapshot = try await makeProvider(credentials: .success(credential()), http: http).fetchUsage()

        #expect(snapshot.provider == .claude)
        #expect(snapshot.planName == "Max (20x)")
        #expect(snapshot.fetchedAt == now)
        #expect(snapshot.windows.map(\.usedPercent) == [0, 29, 56])
    }

    @Test(arguments: [
        (401, [String: String](), ProviderError.unauthorized(status: 401)),
        (403, [:], .unauthorized(status: 403)),
        (429, ["Retry-After": "30"], .rateLimited(retryAfter: 30)),
        (429, [:], .rateLimited(retryAfter: nil)),
        (426, [:], .clientOutdated),
        (500, [:], .serverError(status: 500)),
        (503, [:], .serverError(status: 503)),
        (404, [:], .unexpectedStatus(404)),
    ])
    func nonSuccessStatusesBecomeProviderErrors(status: Int, headers: [String: String], expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"type":"error","error":{"type":"x","message":"y"}}"#, headers: headers)
        await #expect(throws: expected) {
            try await makeProvider(credentials: .success(credential()), http: http).fetchUsage()
        }
    }

    @Test func malformedSuccessBodyIsADecodingError() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "<html>cloudflare</html>")
        await #expect(throws: ProviderError.decoding("claude_json")) {
            try await makeProvider(credentials: .success(credential()), http: http).fetchUsage()
        }
    }

    @Test func transportFailuresPropagateUnchanged() async {
        let http = FakeHTTPClient(responses: [.failure(.responseTooLarge(limit: 1_048_576))])
        await #expect(throws: ProviderError.responseTooLarge(limit: 1_048_576)) {
            try await makeProvider(credentials: .success(credential()), http: http).fetchUsage()
        }
    }

    @Test func credentialFailureShortCircuitsWithoutTouchingTheNetwork() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        await #expect(throws: ProviderError.credentialsExpired) {
            try await makeProvider(credentials: .failure(.credentialsExpired), http: http).fetchUsage()
        }
        #expect(http.requests.isEmpty)
    }

    @Test func linkStateIsLinkedWithDerivedPlanAndOrigin() async {
        let provider = makeProvider(credentials: .success(credential()))
        let expected = AccountInfo(planName: "Max (20x)", accountLabel: nil, origin: "Claude Code")
        #expect(await provider.linkState() == .linked(expected))
        #expect(provider.id == .claude)
    }

    @Test func linkStateWithoutPlanStillLinks() async {
        let bare = ClaudeCredential(
            accessToken: "t", subscriptionType: nil, rateLimitTier: nil, expiresAt: nil, scopes: []
        )
        let provider = makeProvider(credentials: .success(bare))
        let expected = AccountInfo(planName: nil, accountLabel: nil, origin: "Claude Code")
        #expect(await provider.linkState() == .linked(expected))
    }

    @Test(arguments: [
        ProviderError.credentialsNotFound,
        .credentialsExpired,
        .credentialsMalformed("claude_json"),
        .credentialsUnreadable("keychain_interaction_required"),
    ])
    func linkStateReportsEveryCredentialFailure(error: ProviderError) async {
        let provider = makeProvider(credentials: .failure(error))
        #expect(await provider.linkState() == .notLinked(error))
    }

    @Test func liveFactoryWithoutAnyCredentialStoreIsNotLinked() async {
        let provider = ClaudeUsageProvider.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory)),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Date(timeIntervalSince1970: 0) }
        )
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        await #expect(throws: ProviderError.credentialsNotFound) {
            try await provider.fetchUsage()
        }
    }

    @Test func liveFactoryReadsTheKeychainItem() async throws {
        let data = try Fixtures.data("keychain-item-valid", subdirectory: "claude")
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try fixture())
        let provider = ClaudeUsageProvider.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory)),
            http: http,
            keychain: FakeKeychainReader(items: [ClaudeCodeCredentialSource.keychainService: data]),
            fileSystem: FakeFileSystem(),
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
        #expect(await provider.linkState().account?.planName == "Max (20x)")
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.windows.count == 3)
        #expect(http.requests.first?.headers["Authorization"] == "Bearer sk-ant-oat01-FIXTURE-TOKEN-NOT-REAL")
    }

    @Test func secretTokenNeverAppearsInAnyErrorText() async {
        var errors: [ProviderError] = []
        let bodies: [(Int, String)] = [
            (401, #"{"error":{"message":"Invalid bearer token \#(Self.secretToken)"}}"#),
            (429, "slow down"),
            (500, ""),
            (200, "not json"),
            (200, "{}"),
        ]
        for (status, body) in bodies {
            let http = FakeHTTPClient()
            http.enqueue(status: status, json: body)
            do {
                _ = try await makeProvider(credentials: .success(credential()), http: http).fetchUsage()
            } catch {
                errors.append(error)
            }
        }
        let transport = FakeHTTPClient(responses: [.failure(.network("url_error_-1009"))])
        do {
            _ = try await makeProvider(credentials: .success(credential()), http: transport).fetchUsage()
        } catch {
            errors.append(error)
        }

        #expect(errors.count == 6)
        for error in errors {
            #expect(!String(describing: error).contains("SECRET"))
            #expect(!String(reflecting: error).contains("SECRET"))
            #expect(!error.logIdentifier.contains("SECRET"))
            #expect(!error.userMessage.contains("SECRET"))
        }
    }
}
