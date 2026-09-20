import Foundation

/// One request to the endpoint the Muse Code CLI itself uses for its `/usage` panel (ADR 0003).
public struct MuseUsageClient: Sendable {
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.meta.ai/muse-code/key") else {
            preconditionFailure("constant endpoint URL is valid")
        }
        return url
    }()
    public static let apiVersion = "1.0.0"
    public static let userAgent = "AIUsageMonitor/0.1.0 (macOS)"

    let http: any HTTPClient
    let endpoint: URL

    public init(http: any HTTPClient, endpoint: URL = MuseUsageClient.defaultEndpoint) {
        self.http = http
        self.endpoint = endpoint
    }

    /// The RPC only accepts POST with an empty JSON body. It is idempotent: it returns the
    /// account's existing API key plus the current subscription meters and creates or rotates
    /// nothing, which is why ADR 0003 allows it. The key itself is dropped by the mapper.
    public func fetchUsage(token: String) async throws(ProviderError) -> Data {
        let response = try await http.send(request(token: token))
        if let error = response.providerError {
            throw error
        }
        return response.body
    }

    func request(token: String) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [
                "Authorization": "Bearer \(token)",
                "x-api-version": Self.apiVersion,
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": Self.userAgent,
            ],
            body: Data("{}".utf8)
        )
    }
}
