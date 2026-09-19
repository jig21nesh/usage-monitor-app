import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("OpenAIUsageProvider")
struct OpenAIUsageProviderTests {
    typealias Support = OpenAITestSupport

    private func makeProvider(
        credential: Result<OpenAICredential, ProviderError> = .success(Support.credential),
        http: FakeHTTPClient = FakeHTTPClient(),
        userAgent: String = OpenAIUsageClient.defaultUserAgent
    ) -> OpenAIUsageProvider {
        OpenAIUsageProvider(
            credentials: OpenAIStubCredentialSource(result: credential),
            client: OpenAIUsageClient(http: http, userAgent: userAgent),
            now: { Support.now }
        )
    }

    @Test func fetchSendsTheExpectedRequestAndMapsTheBody() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("usage-pro"))
        let provider = makeProvider(http: http)

        let snapshot = try await provider.fetchUsage()

        #expect(provider.id == .openAI)
        #expect(snapshot.windows.map(\.id) == ["openai.session", "openai.weekly"])
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url == OpenAIUsageClient.defaultEndpoint)
        #expect(request.url.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.headers["Authorization"] == "Bearer access-token-value")
        #expect(request.headers["ChatGPT-Account-Id"] == "acct_1")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["User-Agent"] == "AIUsageMonitor/0.1.0 (macOS)")
        #expect(request.body == nil)
    }

    @Test func customUserAgentIsSent() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("usage-pro"))
        _ = try await makeProvider(http: http, userAgent: "Custom/1").fetchUsage()
        #expect(http.requests.first?.headers["User-Agent"] == "Custom/1")
    }

    @Test func accountHeaderIsOmittedWhenUnknown() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("usage-pro"))
        let credential = OpenAICredential(accessToken: "t", accountID: nil, planType: nil, email: nil)
        _ = try await makeProvider(credential: .success(credential), http: http).fetchUsage()
        #expect(http.requests.first?.headers["ChatGPT-Account-Id"] == nil)
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
    func mapsHTTPStatuses(status: Int, headers: [String: String], expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"detail":"nope"}"#, headers: headers)
        await #expect(throws: expected) {
            try await makeProvider(http: http).fetchUsage()
        }
    }

    @Test func transportErrorsPassThrough() async {
        let http = FakeHTTPClient(responses: [.failure(.network("url_error_-1009"))])
        await #expect(throws: ProviderError.network("url_error_-1009")) {
            try await makeProvider(http: http).fetchUsage()
        }
    }

    @Test func malformedBodyIsDecodingError() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("usage-malformed"))
        await #expect(throws: ProviderError.decoding("openai_json")) {
            try await makeProvider(http: http).fetchUsage()
        }
    }

    @Test func credentialFailureShortCircuitsBeforeAnyRequest() async {
        let http = FakeHTTPClient()
        let provider = makeProvider(credential: .failure(.credentialsExpired), http: http)
        await #expect(throws: ProviderError.credentialsExpired) { try await provider.fetchUsage() }
        #expect(http.requests.isEmpty)
    }

    @Test func linkStateReflectsTheCredential() async {
        let linked = await makeProvider().linkState()
        #expect(linked == .linked(AccountInfo(planName: "Pro", accountLabel: "me@example.com", origin: "Codex CLI")))

        let unlinked = await makeProvider(credential: .failure(.credentialsNotFound)).linkState()
        #expect(unlinked == .notLinked(.credentialsNotFound))

        let bare = OpenAICredential(accessToken: "t", accountID: nil, planType: nil, email: nil)
        let bareLink = await makeProvider(credential: .success(bare)).linkState()
        #expect(bareLink == .linked(AccountInfo(planName: nil, accountLabel: nil, origin: "Codex CLI")))
    }

    @Test func liveFactoryReadsTheCodexAuthFile() async throws {
        let environment = UserEnvironment(homeDirectory: Support.home)
        var fileSystem = FakeFileSystem()
        fileSystem.add(Support.home.appending(path: ".codex/auth.json"), contents: Support.authFile())
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("usage-plus-weekly-only"))

        let provider = OpenAIUsageProvider.live(
            environment: environment,
            http: http,
            keychain: FakeKeychainReader(),
            fileSystem: fileSystem,
            now: { Support.now }
        )

        #expect(provider.id == .openAI)
        #expect(await provider.linkState().isLinked)
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.planName == "Plus")
        #expect(http.requests.first?.headers["ChatGPT-Account-Id"] == "acct_file")
    }

    @Test func liveFactoryWithoutAuthFileIsNotLinked() async {
        let provider = OpenAIUsageProvider.live(
            environment: UserEnvironment(homeDirectory: Support.home),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Support.now }
        )
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        await #expect(throws: ProviderError.credentialsNotFound) { try await provider.fetchUsage() }
    }

    @Test func noFailurePathLeaksTheToken() async throws {
        let secretToken = "eyJhbGciOiJSUzI1NiJ9.SECRETSECRET.sig"
        let credential = OpenAICredential(
            accessToken: secretToken,
            accountID: "acct_SECRET",
            planType: nil,
            email: "SECRET@x"
        )
        var errors: [ProviderError] = []

        let scripted: [(Int, String)] = [
            (401, "{}"), (429, "{}"), (500, "oops"), (200, "{not json"), (200, "{}"), (404, ""),
        ]
        for (status, body) in scripted {
            let http = FakeHTTPClient()
            http.enqueue(status: status, json: body)
            do {
                _ = try await makeProvider(credential: .success(credential), http: http).fetchUsage()
            } catch {
                errors.append(error)
            }
        }
        let network = FakeHTTPClient(responses: [.failure(.network("x"))])
        do {
            _ = try await makeProvider(credential: .success(credential), http: network).fetchUsage()
        } catch {
            errors.append(error)
        }
        let source = Support.makeSource(contents: "{\"tokens\":{\"access_token\":\"\(secretToken)\"}, \"broken\"")
        do {
            _ = try source.load()
        } catch {
            errors.append(error)
        }

        #expect(errors.count == 8)
        for error in errors {
            #expect(!String(describing: error).contains("SECRET"))
            #expect(!error.logIdentifier.contains("SECRET"))
            #expect(!error.userMessage.contains("SECRET"))
        }
    }
}
