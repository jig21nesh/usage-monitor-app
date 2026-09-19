import Foundation

/// The only production `HTTPClient`. Ephemeral, cookie-less and cache-less so nothing a vendor
/// sends back is ever persisted (ADR 0002), with a hard cap on body size (ADR 0003).
public final class URLSessionHTTPClient: HTTPClient, Sendable {
    public static let defaultMaxBodyBytes = 1_048_576

    private let session: URLSession
    private let maxBodyBytes: Int

    public init(
        session: URLSession = URLSessionHTTPClient.makeSession(),
        maxBodyBytes: Int = URLSessionHTTPClient.defaultMaxBodyBytes
    ) {
        self.session = session
        self.maxBodyBytes = maxBodyBytes
    }

    public static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        return URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws(ProviderError) -> HTTPResponse {
        let urlRequest = makeURLRequest(request)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch {
            throw Self.mapTransportError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .network("non_http_response")
        }
        if http.expectedContentLength > Int64(maxBodyBytes) {
            throw .responseTooLarge(limit: maxBodyBytes)
        }
        let body = try await readBody(bytes)
        return HTTPResponse(statusCode: http.statusCode, headers: Self.normalizedHeaders(http), body: body)
    }

    private func readBody(_ bytes: URLSession.AsyncBytes) async throws(ProviderError) -> Data {
        var body = Data()
        do {
            for try await byte in bytes {
                body.append(byte)
                if body.count > maxBodyBytes {
                    throw ProviderError.responseTooLarge(limit: maxBodyBytes)
                }
            }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw Self.mapTransportError(error)
        }
        return body
    }

    private func makeURLRequest(_ request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    /// Only the error code survives: `URLError` descriptions can embed request details.
    static func mapTransportError(_ error: any Error) -> ProviderError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .network("unknown") }
        if urlError.code == .cancelled { return .cancelled }
        return .network("url_error_\(urlError.code.rawValue)")
    }

    static func normalizedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            headers[name.lowercased()] = value
        }
        return headers
    }
}
