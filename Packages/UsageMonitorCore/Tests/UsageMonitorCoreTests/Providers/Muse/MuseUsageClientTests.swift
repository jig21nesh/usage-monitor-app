import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("MuseUsageClient")
struct MuseUsageClientTests {
    typealias Support = MuseTestSupport

    @Test func sendsAnEmptyJSONPostWithTheDocumentedHeaders() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"{"is_subs_active":true}"#)
        let body = try await MuseUsageClient(http: http).fetchUsage(token: Support.token)
        #expect(String(data: body, encoding: .utf8) == #"{"is_subs_active":true}"#)

        let request = try #require(http.requests.first)
        #expect(request.method == .post)
        #expect(request.url == MuseUsageClient.defaultEndpoint)
        #expect(request.url.absoluteString == "https://api.meta.ai/muse-code/key")
        #expect(request.body == Data("{}".utf8))
        #expect(request.headers["Authorization"] == "Bearer \(Support.token)")
        #expect(request.headers["x-api-version"] == "1.0.0")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["User-Agent"] == "AIUsageMonitor/0.1.0 (macOS)")
        #expect(request.headers.count == 5)
    }

    @Test(arguments: [
        (401, ProviderError.unauthorized(status: 401)),
        (403, .unauthorized(status: 403)),
        (426, .clientOutdated),
        (429, .rateLimited(retryAfter: nil)),
        (500, .serverError(status: 500)),
        (503, .serverError(status: 503)),
        (418, .unexpectedStatus(418)),
    ])
    func statusCodesMapToProviderErrors(status: Int, expected: ProviderError) async {
        let http = FakeHTTPClient()
        http.enqueue(status: status, json: #"{"error":"dca:SECRETTOKEN123"}"#)
        await #expect(throws: expected) {
            try await MuseUsageClient(http: http).fetchUsage(token: Support.token)
        }
    }

    @Test func rateLimitCarriesRetryAfter() async {
        let http = FakeHTTPClient()
        http.enqueue(status: 429, json: "{}", headers: ["Retry-After": "120"])
        await #expect(throws: ProviderError.rateLimited(retryAfter: 120)) {
            try await MuseUsageClient(http: http).fetchUsage(token: Support.token)
        }
    }

    @Test func transportFailuresPassThrough() async {
        let http = FakeHTTPClient(responses: [.failure(.network("url_error_-1009"))])
        await #expect(throws: ProviderError.network("url_error_-1009")) {
            try await MuseUsageClient(http: http).fetchUsage(token: Support.token)
        }
    }

    @Test func customEndpointIsHonoured() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: "{}")
        let endpoint = try #require(URL(string: "https://staging.invalid/muse-code/key"))
        _ = try await MuseUsageClient(http: http, endpoint: endpoint).fetchUsage(token: Support.token)
        #expect(http.requests.first?.url == endpoint)
    }
}
