import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("GrokUsageClient")
struct GrokUsageClientTests {
    typealias Env = GrokTestEnvironment

    @Test func sendsTheHeadersTheProxyExpects() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        let client = GrokUsageClient(http: http, clientVersion: "9.9.9")

        _ = try await client.fetchBilling(with: Env.credential(token: "tok", userID: "user-1"))

        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        #expect(request.headers["Authorization"] == "Bearer tok")
        #expect(request.headers["X-XAI-Token-Auth"] == "xai-grok-cli")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["x-grok-client-version"] == "9.9.9")
        #expect(request.headers["x-userid"] == "user-1")
        #expect(request.headers["User-Agent"] == GrokUsageClient.userAgent)
        #expect(request.headers.count == 6)
        #expect(request.body == nil)
    }

    @Test func defaultsToTheReleasedCLIVersion() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        _ = try await GrokUsageClient(http: http).fetchBilling(with: Env.credential())
        #expect(http.requests.first?.headers["x-grok-client-version"] == GrokUsageClient.defaultClientVersion)
    }

    @Test(arguments: [nil, ""])
    func omitsUserIDHeaderWhenUnknown(userID: String?) async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        _ = try await GrokUsageClient(http: http).fetchBilling(with: Env.credential(userID: userID))
        #expect(http.requests.first?.headers["x-userid"] == nil)
        #expect(http.requests.first?.headers.count == 5)
    }

    @Test func returnsTheBodyOnSuccess() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"{"config":{}}"#)
        let body = try await GrokUsageClient(http: http).fetchBilling(with: Env.credential())
        #expect(String(data: body, encoding: .utf8) == #"{"config":{}}"#)
    }

    @Test(arguments: [
        (401, ProviderError.unauthorized(status: 401)),
        (403, ProviderError.unauthorized(status: 403)),
        (426, ProviderError.clientOutdated),
        (429, ProviderError.rateLimited(retryAfter: nil)),
        (500, ProviderError.serverError(status: 500)),
        (503, ProviderError.serverError(status: 503)),
        (404, ProviderError.unexpectedStatus(404)),
    ])
    func mapsFailureStatuses(status: Int, expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"error":"nope"}"#)
        await #expect(throws: expected) {
            try await GrokUsageClient(http: http).fetchBilling(with: Env.credential())
        }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "240"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 240)) {
            try await GrokUsageClient(http: http).fetchBilling(with: Env.credential())
        }
    }

    @Test func transportErrorsPassThrough() async {
        let http = FakeHTTPClient(responses: [.failure(.network("url_error_-1009"))])
        await #expect(throws: ProviderError.network("url_error_-1009")) {
            try await GrokUsageClient(http: http).fetchBilling(with: Env.credential())
        }
    }
}
