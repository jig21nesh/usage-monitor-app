import Foundation
import Synchronization

/// Per-URL stub so tests can run in parallel: each test registers its own unique URL.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(_ url: URL, handler: @escaping Handler) {
        handlers.withLock { $0[url.absoluteString] = handler }
    }

    static func unregister(_ url: URL) {
        handlers.withLock { _ = $0.removeValue(forKey: url.absoluteString) }
    }

    static func uniqueURL(_ label: String = "stub") -> URL {
        URL(string: "https://\(label).invalid/\(UUID().uuidString)")!
    }

    static func response(for url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        guard let handler = Self.handlers.withLock({ $0[key] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
