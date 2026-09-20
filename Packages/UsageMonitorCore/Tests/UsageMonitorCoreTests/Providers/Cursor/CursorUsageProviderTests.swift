import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CursorUsageProvider")
struct CursorUsageProviderTests {
    private struct StaticCredentials: CredentialSource {
        let result: Result<CursorCredential, ProviderError>

        func load() throws(ProviderError) -> CursorCredential { try result.get() }
    }

    private func provider(
        credential: Result<CursorCredential, ProviderError> = .success(CursorTestData.credential()),
        http: FakeHTTPClient
    ) -> CursorUsageProvider {
        CursorUsageProvider(
            credentials: StaticCredentials(result: credential),
            client: CursorUsageClient(http: http),
            now: { CursorTestData.now }
        )
    }

    @Test func sendsAReadOnlyPostWithTheExpectedHeaders() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Fixtures.data("period-usage-pro", subdirectory: "cursor"))
        let snapshot = try await provider(http: http).fetchUsage()

        #expect(snapshot.windows.count == 2)
        let request = try #require(http.requests.first)
        #expect(request.method == .post)
        #expect(request.url == CursorUsageClient.defaultEndpoint)
        #expect(request.body == Data("{}".utf8))
        #expect(request.headers["Authorization"] == "Bearer \(CursorTestData.credential().accessToken)")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Connect-Protocol-Version"] == "1")
        #expect(request.headers["User-Agent"] == "AIUsageMonitor/0.1.0 (macOS)")
    }

    @Test(arguments: [
        (401, ProviderError.unauthorized(status: 401)),
        (403, .unauthorized(status: 403)),
        (426, .clientOutdated),
        (500, .serverError(status: 500)),
        (503, .serverError(status: 503)),
        (404, .unexpectedStatus(404)),
    ])
    func httpFailuresMapThroughTheSharedTable(status: Int, expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"error":"SECRETSECRET"}"#)
        await #expect(throws: expected) { try await provider(http: http).fetchUsage() }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "120"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 120)) {
            try await provider(http: http).fetchUsage()
        }
    }

    @Test func transportAndSizeFailuresPropagate() async {
        let network = FakeHTTPClient(responses: [.failure(.network("url_error_-1009"))])
        await #expect(throws: ProviderError.network("url_error_-1009")) {
            try await provider(http: network).fetchUsage()
        }
        let large = FakeHTTPClient(responses: [.failure(.responseTooLarge(limit: 1_048_576))])
        await #expect(throws: ProviderError.responseTooLarge(limit: 1_048_576)) {
            try await provider(http: large).fetchUsage()
        }
    }

    @Test func credentialFailuresSkipTheNetwork() async {
        let http = FakeHTTPClient()
        await #expect(throws: ProviderError.credentialsExpired) {
            try await provider(credential: .failure(.credentialsExpired), http: http).fetchUsage()
        }
        #expect(http.requests.isEmpty)
    }

    @Test func malformedBodyIsADecodingError() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "SECRETSECRET not json")
        await #expect(throws: ProviderError.decoding("cursor_json")) { try await provider(http: http).fetchUsage() }
    }

    @Test func linkStateReportsPlanAndEmailWithoutNetwork() async {
        let http = FakeHTTPClient()
        let linked = await provider(http: http).linkState()
        #expect(linked == .linked(AccountInfo(planName: "Pro", accountLabel: "someone@example.com", origin: "Cursor")))
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: [
        ProviderError.credentialsNotFound, .credentialsExpired, .credentialsMalformed("cursor_token"),
        .credentialsUnreadable("cursor_db_busy"),
    ])
    func linkStateReportsEveryCredentialFailure(error: ProviderError) async {
        let state = await provider(credential: .failure(error), http: FakeHTTPClient()).linkState()
        #expect(state == .notLinked(error))
    }

    @Test func noFailurePathLeaksTheToken() async {
        let bodies = [
            (401, #"{"error":"token SECRETSECRET rejected"}"#),
            (429, #"{"error":"SECRETSECRET"}"#),
            (500, "SECRETSECRET"),
            (200, "SECRETSECRET"),
            (200, "{}"),
        ]
        for (status, body) in bodies {
            let http = FakeHTTPClient()
            http.enqueue(status: status, json: body)
            do {
                _ = try await provider(http: http).fetchUsage()
                Issue.record("expected failure for status \(status)")
            } catch {
                let texts = [
                    String(describing: error), String(reflecting: error), error.logIdentifier, error.userMessage,
                ]
                #expect(!texts.joined().contains("SECRET"), "status \(status) leaked")
            }
        }
        let transport = FakeHTTPClient(responses: [.failure(.network("SECRETSECRET"))])
        do {
            _ = try await provider(http: transport).fetchUsage()
        } catch {
            // The transport layer never puts secrets into its identifier; this path only checks the wiring.
            #expect(error.logIdentifier.hasPrefix("network:"))
        }
    }

    @Test func liveFactoryBuildsWithoutTouchingTheNetwork() async {
        let live = CursorUsageProvider.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent-home")),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { CursorTestData.now }
        )
        #expect(live.id == .cursor)
        #expect(live.minimumPollInterval == nil)
        #expect(await live.linkState() == .notLinked(.credentialsNotFound))
    }
}
