import Foundation

public struct HTTPRequest: Sendable, Hashable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: Method = .get,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 20
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public let statusCode: Int
    /// Header names are lower-cased on construction so lookups are case-insensitive.
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// `Retry-After` in seconds when the vendor sent a delta-seconds value.
    public var retryAfterSeconds: TimeInterval? {
        guard let raw = header("retry-after")?.trimmingCharacters(in: .whitespaces),
              let seconds = TimeInterval(raw), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws(ProviderError) -> HTTPResponse
}
