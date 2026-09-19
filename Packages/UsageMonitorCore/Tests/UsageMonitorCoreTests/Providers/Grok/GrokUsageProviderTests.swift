import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("GrokUsageProvider")
struct GrokUsageProviderTests {
    typealias Env = GrokTestEnvironment

    private func makeProvider(
        authJSON: String? = GrokAuthJSON.nested(),
        http: FakeHTTPClient = FakeHTTPClient()
    ) -> (GrokUsageProvider, FakeHTTPClient) {
        let provider = GrokUsageProvider.live(
            environment: Env.environment(),
            http: http,
            keychain: FakeKeychainReader(),
            fileSystem: Env.fileSystem(authJSON: authJSON),
            now: { Env.now }
        )
        return (provider, http)
    }

    @Test func liveProviderFetchesAndMapsUsage() async throws {
        let (provider, http) = makeProvider()
        http.enqueue(status: 200, body: try Fixtures.data("billing-full", subdirectory: "grok"))

        let snapshot = try await provider.fetchUsage()

        #expect(provider.id == .grok)
        #expect(snapshot.provider == .grok)
        #expect(snapshot.planName == "SuperGrok")
        #expect(snapshot.windows.first?.usedPercent == 58)
        #expect(snapshot.fetchedAt == Env.now)
        #expect(http.requests.count == 1)
        #expect(http.requests.first?.headers["Authorization"] == "Bearer grok-token")
    }

    @Test func linkStateReflectsTheCredentialFile() async {
        let (linked, _) = makeProvider()
        #expect(await linked.linkState() == .linked(AccountInfo(
            planName: nil, accountLabel: "me@example.com", origin: "Grok Build CLI"
        )))

        let (missing, _) = makeProvider(authJSON: nil)
        #expect(await missing.linkState() == .notLinked(.credentialsNotFound))

        let (expired, _) = makeProvider(authJSON: GrokAuthJSON.nested(expiresAt: "2020-01-01T00:00:00Z"))
        #expect(await expired.linkState() == .notLinked(.credentialsExpired))
    }

    @Test func missingCredentialFailsBeforeAnyRequest() async {
        let (provider, http) = makeProvider(authJSON: nil)
        await #expect(throws: ProviderError.credentialsNotFound) { try await provider.fetchUsage() }
        #expect(http.requests.isEmpty)
    }

    @Test func httpAndMappingFailuresPropagate() async {
        let (limited, http) = makeProvider()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "60"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 60)) { try await limited.fetchUsage() }

        let (broken, brokenHTTP) = makeProvider()
        brokenHTTP.enqueue(status: 200, json: #"{"subscriptionTier":"SuperGrok"}"#)
        await #expect(throws: ProviderError.decoding("grok_no_config")) { try await broken.fetchUsage() }
    }

    @Test func noFailurePathEverMentionsTheToken() async {
        let token = "SECRETSECRETTOKEN"
        var failures: [ProviderError] = []

        for status in [401, 403, 426, 429, 500, 404] {
            let (provider, http) = makeProvider(authJSON: GrokAuthJSON.nested(key: token))
            http.enqueue(status: status, json: #"{"error":"SECRET-in-body-must-not-leak"}"#)
            failures.append(await failure(of: provider))
        }
        for body in ["not json", "{}", #"{"config":{"creditUsagePercent":"NaN"}}"#] {
            let (provider, http) = makeProvider(authJSON: GrokAuthJSON.nested(key: token))
            http.enqueue(status: 200, json: body)
            failures.append(await failure(of: provider))
        }
        for authJSON in [
            GrokAuthJSON.nested(key: token, expiresAt: "2020-01-01T00:00:00Z"),
            #"{"key": "\#(token)", "expires_at": ["broken"], "user_id": 5, "extra": "SECRET"}"#,
            "{\"https://auth.x.ai::x\": {\"key\": \"\(token)\"}} trailing garbage",
        ] {
            let (provider, http) = makeProvider(authJSON: authJSON)
            http.enqueue(status: 200, json: "{}")
            failures.append(await failure(of: provider))
        }
        let (network, networkHTTP) = makeProvider(authJSON: GrokAuthJSON.nested(key: token))
        networkHTTP.enqueue(.failure(.network("url_error_-1001")))
        failures.append(await failure(of: network))

        #expect(failures.count == 13)
        for error in failures {
            #expect(!String(describing: error).contains("SECRET"))
            #expect(!String(reflecting: error).contains("SECRET"))
            #expect(!error.logIdentifier.contains("SECRET"))
            #expect(!error.userMessage.contains("SECRET"))
        }
    }

    private func failure(of provider: GrokUsageProvider) async -> ProviderError {
        do {
            _ = try await provider.fetchUsage()
            Issue.record("expected a failure")
            return .cancelled
        } catch {
            return error
        }
    }
}
