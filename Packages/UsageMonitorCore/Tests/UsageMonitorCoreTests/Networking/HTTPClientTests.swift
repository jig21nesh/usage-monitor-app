import Foundation
import Synchronization
import Testing
@testable import UsageMonitorCore

@Suite("HTTPResponse and HTTPRequest")
struct HTTPResponseTests {
    @Test func lowercasesHeaderNamesForCaseInsensitiveLookup() {
        let response = HTTPResponse(statusCode: 200, headers: ["Retry-After": "30", "X-Test": "a"])
        #expect(response.header("retry-after") == "30")
        #expect(response.header("X-TEST") == "a")
        #expect(response.headers["x-test"] == "a")
    }

    @Test(arguments: [("30", 30.0), (" 12.5 ", 12.5), ("0", 0.0)])
    func parsesRetryAfterSeconds(raw: String, expected: TimeInterval) {
        #expect(HTTPResponse(statusCode: 429, headers: ["Retry-After": raw]).retryAfterSeconds == expected)
    }

    @Test(arguments: ["", "soon", "-1", "nan", "Wed, 21 Oct 2026 07:28:00 GMT"])
    func ignoresUnparseableRetryAfter(raw: String) {
        #expect(HTTPResponse(statusCode: 429, headers: ["Retry-After": raw]).retryAfterSeconds == nil)
    }

    @Test func requestDefaults() {
        let request = HTTPRequest(url: URL(string: "https://example.invalid/usage")!)
        #expect(request.method == .get)
        #expect(request.headers.isEmpty)
        #expect(request.body == nil)
        #expect(request.timeout == 20)
    }
}

@Suite("URLSessionHTTPClient")
struct URLSessionHTTPClientTests {
    private func makeClient(maxBodyBytes: Int = URLSessionHTTPClient.defaultMaxBodyBytes) -> URLSessionHTTPClient {
        URLSessionHTTPClient(
            session: URLSessionHTTPClient.makeSession(protocolClasses: [StubURLProtocol.self]),
            maxBodyBytes: maxBodyBytes
        )
    }

    @Test func deliversStatusHeadersAndBody() async throws {
        let url = StubURLProtocol.uniqueURL()
        defer { StubURLProtocol.unregister(url) }
        let seenAuthorization = Mutex<String?>(nil)
        StubURLProtocol.register(url) { request in
            seenAuthorization.withLock { $0 = request.value(forHTTPHeaderField: "Authorization") }
            let response = StubURLProtocol.response(for: url, status: 201, headers: [
                "Content-Type": "application/json", "Retry-After": "5",
            ])
            return (response, Data(#"{"ok":true}"#.utf8))
        }

        let response = try await makeClient().send(HTTPRequest(url: url, headers: ["Authorization": "Bearer test"]))

        #expect(response.statusCode == 201)
        #expect(response.header("content-type") == "application/json")
        #expect(response.retryAfterSeconds == 5)
        #expect(String(data: response.body, encoding: .utf8) == #"{"ok":true}"#)
        #expect(seenAuthorization.withLock { $0 } == "Bearer test")
    }

    @Test func rejectsOversizedBodyAnnouncedByContentLength() async {
        let url = StubURLProtocol.uniqueURL()
        defer { StubURLProtocol.unregister(url) }
        StubURLProtocol.register(url) { _ in
            (StubURLProtocol.response(for: url, status: 200, headers: ["Content-Length": "2048"]), Data(count: 2048))
        }
        await #expect(throws: ProviderError.responseTooLarge(limit: 1024)) {
            try await makeClient(maxBodyBytes: 1024).send(HTTPRequest(url: url))
        }
    }

    @Test func rejectsOversizedStreamedBodyWithoutContentLength() async {
        let url = StubURLProtocol.uniqueURL()
        defer { StubURLProtocol.unregister(url) }
        StubURLProtocol.register(url) { _ in
            (StubURLProtocol.response(for: url, status: 200), Data(count: 4096))
        }
        await #expect(throws: ProviderError.responseTooLarge(limit: 1024)) {
            try await makeClient(maxBodyBytes: 1024).send(HTTPRequest(url: url))
        }
    }

    @Test func mapsTransportFailuresToNetworkErrorsWithoutDetails() async {
        let url = StubURLProtocol.uniqueURL()
        defer { StubURLProtocol.unregister(url) }
        StubURLProtocol.register(url) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: ProviderError.network("url_error_-1009")) {
            try await makeClient().send(HTTPRequest(url: url))
        }
    }

    @Test func unregisteredURLFailsAsNetworkError() async {
        await #expect(throws: ProviderError.network("url_error_-1002")) {
            try await makeClient().send(HTTPRequest(url: StubURLProtocol.uniqueURL("unregistered")))
        }
    }

    @Test func transportErrorMapping() {
        #expect(URLSessionHTTPClient.mapTransportError(CancellationError()) == .cancelled)
        #expect(URLSessionHTTPClient.mapTransportError(URLError(.cancelled)) == .cancelled)
        #expect(URLSessionHTTPClient.mapTransportError(URLError(.timedOut)) == .network("url_error_-1001"))
        #expect(URLSessionHTTPClient.mapTransportError(NSError(domain: "x", code: 1)) == .network("unknown"))
    }

    @Test func sessionIsEphemeralCookielessAndUncached() {
        let configuration = URLSessionHTTPClient.makeSession().configuration
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}
