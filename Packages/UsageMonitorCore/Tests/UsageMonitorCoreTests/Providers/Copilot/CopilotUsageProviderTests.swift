import Foundation
import Testing
@testable import UsageMonitorCore

struct StaticCopilotCredentials: CredentialSource {
    let result: Result<CopilotCredential, ProviderError>

    func load() throws(ProviderError) -> CopilotCredential {
        try result.get()
    }
}

@Suite("CopilotUsageProvider")
struct CopilotUsageProviderTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let credential = CopilotCredential(token: "gho_SECRETSECRET", source: "GitHub CLI", login: "octocat")

    private func makeProvider(
        http: FakeHTTPClient,
        credentials: Result<CopilotCredential, ProviderError>? = nil
    ) -> CopilotUsageProvider {
        let fixedNow = now
        return CopilotUsageProvider(
            credentials: StaticCopilotCredentials(result: credentials ?? .success(credential)),
            client: CopilotUsageClient(http: http),
            now: { fixedNow }
        )
    }

    @Test func sendsTheExactRequest() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Fixtures.data("user-individual", subdirectory: "copilot"))
        _ = try await makeProvider(http: http).fetchUsage()
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url == URL(string: "https://api.github.com/copilot_internal/user"))
        #expect(request.headers["Authorization"] == "token gho_SECRETSECRET")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["User-Agent"] == "AIUsageMonitor/0.1.0 (macOS)")
        #expect(request.headers.count == 3)
        #expect(request.body == nil)
    }

    @Test func successMapsSnapshotAndLinkState() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Fixtures.data("user-individual", subdirectory: "copilot"))
        let provider = makeProvider(http: http)
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.fetchedAt == now)
        let expectedLink = LinkState.linked(AccountInfo(planName: nil, accountLabel: "octocat", origin: "GitHub CLI"))
        #expect(await provider.linkState() == expectedLink)
    }

    @Test(arguments: [
        (401, ProviderError.unauthorized(status: 401)),
        (403, .unauthorized(status: 403)),
        (404, .unauthorized(status: 404)),
        (426, .clientOutdated),
        (429, .rateLimited(retryAfter: nil)),
        (500, .serverError(status: 500)),
        (502, .serverError(status: 502)),
        (418, .unexpectedStatus(418)),
    ])
    func statusCodesMapToProviderErrors(status: Int, expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"message":"nope"}"#)
        await #expect(throws: expected) { try await makeProvider(http: http).fetchUsage() }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "120"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 120)) {
            try await makeProvider(http: http).fetchUsage()
        }
    }

    @Test func missingCredentialsShortCircuit() async {
        let http = FakeHTTPClient()
        let provider = makeProvider(http: http, credentials: .failure(.credentialsNotFound))
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        await #expect(throws: ProviderError.credentialsNotFound) { try await provider.fetchUsage() }
        #expect(http.requests.isEmpty)
    }

    @Test func liveRegistryWithoutStoresReportsNotLinked() async {
        let provider = CopilotUsageProvider.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory)),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Date(timeIntervalSince1970: 0) }
        )
        #expect(provider.id == .copilot)
        #expect(provider.minimumPollInterval == nil)
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
    }

    @Test func noFailurePathLeaksTheToken() async throws {
        let failures: [Result<HTTPResponse, ProviderError>] = [
            .success(HTTPResponse(statusCode: 401, body: Data(#"{"message":"bad token gho_SECRETSECRET"}"#.utf8))),
            .success(HTTPResponse(statusCode: 404, body: Data("gho_SECRETSECRET".utf8))),
            .success(HTTPResponse(statusCode: 429, headers: ["Retry-After": "5"])),
            .success(HTTPResponse(statusCode: 500, body: Data("gho_SECRETSECRET".utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("{not json gho_SECRETSECRET".utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("{}".utf8))),
            .success(HTTPResponse(statusCode: 200, body: try Fixtures.data("user-unlimited", subdirectory: "copilot"))),
            .failure(.network("url_error_-1009")),
            .failure(.responseTooLarge(limit: 1)),
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
