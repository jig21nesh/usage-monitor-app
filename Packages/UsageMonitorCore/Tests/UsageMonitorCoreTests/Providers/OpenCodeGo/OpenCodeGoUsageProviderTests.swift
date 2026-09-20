import Foundation
import Testing
@testable import UsageMonitorCore

struct StaticOpenCodeCredentials: CredentialSource {
    let result: Result<OpenCodeCredential, ProviderError>

    func load() throws(ProviderError) -> OpenCodeCredential {
        try result.get()
    }
}

@Suite("OpenCodeGoUsageProvider")
struct OpenCodeGoUsageProviderTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let credential = OpenCodeCredential(key: "sk-SECRETSECRET")

    private func makeProvider(
        http: FakeHTTPClient,
        credentials: Result<OpenCodeCredential, ProviderError>? = nil
    ) -> OpenCodeGoUsageProvider {
        let fixedNow = now
        return OpenCodeGoUsageProvider(
            credentials: StaticOpenCodeCredentials(result: credentials ?? .success(credential)),
            client: OpenCodeGoUsageClient(http: http),
            now: { fixedNow }
        )
    }

    @Test func sendsTheExactRequest() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Fixtures.data("usage-go", subdirectory: "opencode"))
        _ = try await makeProvider(http: http).fetchUsage()
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url == URL(string: "https://opencode.ai/zen/go/v1/usage"))
        #expect(request.headers["Authorization"] == "Bearer sk-SECRETSECRET")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["User-Agent"] == "AIUsageMonitor/0.1.0 (macOS)")
        #expect(request.headers.count == 3)
    }

    @Test func successMapsSnapshotAndLinkState() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Fixtures.data("usage-go", subdirectory: "opencode"))
        let provider = makeProvider(http: http)
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.planName == "Go")
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.fetchedAt == now)
        let expectedLink = LinkState.linked(AccountInfo(planName: "Go", accountLabel: nil, origin: "OpenCode CLI"))
        #expect(await provider.linkState() == expectedLink)
    }

    @Test(arguments: [
        (401, ProviderError.unauthorized(status: 401)),
        (403, .unauthorized(status: 403)),
        (404, .unexpectedStatus(404)),
        (429, .rateLimited(retryAfter: nil)),
        (500, .serverError(status: 500)),
    ])
    func statusCodesMapToProviderErrors(status: Int, expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"error":"nope"}"#)
        await #expect(throws: expected) { try await makeProvider(http: http).fetchUsage() }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "30"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 30)) {
            try await makeProvider(http: http).fetchUsage()
        }
    }

    @Test func missingCredentialsShortCircuit() async {
        let http = FakeHTTPClient()
        let provider = makeProvider(http: http, credentials: .failure(.credentialsMalformed("opencode_json")))
        #expect(await provider.linkState() == .notLinked(.credentialsMalformed("opencode_json")))
        await #expect(throws: ProviderError.credentialsMalformed("opencode_json")) { try await provider.fetchUsage() }
        #expect(http.requests.isEmpty)
    }

    @Test func liveRegistryWithoutStoresReportsNotLinked() async {
        let provider = OpenCodeGoUsageProvider.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory)),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Date(timeIntervalSince1970: 0) }
        )
        #expect(provider.id == .opencodeGo)
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
    }

    @Test func noFailurePathLeaksTheKey() async throws {
        let failures: [Result<HTTPResponse, ProviderError>] = [
            .success(HTTPResponse(statusCode: 401, body: Data(#"{"error":"bad key sk-SECRETSECRET"}"#.utf8))),
            .success(HTTPResponse(statusCode: 429, headers: ["Retry-After": "5"])),
            .success(HTTPResponse(statusCode: 503, body: Data("sk-SECRETSECRET".utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("{oops sk-SECRETSECRET".utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("{}".utf8))),
            .success(HTTPResponse(statusCode: 200, body: try Fixtures.data("usage-empty", subdirectory: "opencode"))),
            .failure(.network("url_error_-1001")),
        ]
        for failure in failures {
            let http = FakeHTTPClient(responses: [failure])
            do {
                _ = try await makeProvider(http: http).fetchUsage()
                Issue.record("expected a failure")
            } catch {
                #expect(!String(describing: error).contains("SECRET"))
                #expect(!String(reflecting: error).contains("SECRET"))
                #expect(!error.logIdentifier.contains("SECRET"))
                #expect(!error.userMessage.contains("SECRET"))
            }
        }
    }
}
