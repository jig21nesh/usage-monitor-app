import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("HTTPResponse.providerError")
struct ProviderErrorMappingTests {
    @Test(arguments: [200, 201, 204, 299])
    func successStatusesMapToNil(status: Int) {
        #expect(HTTPResponse(statusCode: status).providerError == nil)
    }

    @Test func authStatusesMapToUnauthorized() {
        #expect(HTTPResponse(statusCode: 401).providerError == .unauthorized(status: 401))
        #expect(HTTPResponse(statusCode: 403).providerError == .unauthorized(status: 403))
    }

    @Test func rateLimitCarriesRetryAfter() {
        let limited = HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"])
        #expect(limited.providerError == .rateLimited(retryAfter: 120))
        #expect(HTTPResponse(statusCode: 429).providerError == .rateLimited(retryAfter: nil))
    }

    @Test func otherStatuses() {
        #expect(HTTPResponse(statusCode: 426).providerError == .clientOutdated)
        #expect(HTTPResponse(statusCode: 500).providerError == .serverError(status: 500))
        #expect(HTTPResponse(statusCode: 503).providerError == .serverError(status: 503))
        #expect(HTTPResponse(statusCode: 404).providerError == .unexpectedStatus(404))
        #expect(HTTPResponse(statusCode: 302).providerError == .unexpectedStatus(302))
    }
}
