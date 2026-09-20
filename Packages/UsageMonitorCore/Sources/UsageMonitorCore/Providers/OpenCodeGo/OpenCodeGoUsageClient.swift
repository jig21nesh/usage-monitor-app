import Foundation

/// One read-only request to the usage endpoint the OpenCode CLI's Go plan uses (ADR 0008).
public struct OpenCodeGoUsageClient: Sendable {
    public static let defaultUserAgent = "AIUsageMonitor/0.1.0 (macOS)"

    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://opencode.ai/zen/go/v1/usage") else {
            preconditionFailure("constant endpoint URL is valid")
        }
        return url
    }()

    private let http: any HTTPClient
    private let userAgent: String
    private let endpoint: URL

    public init(
        http: any HTTPClient,
        userAgent: String = OpenCodeGoUsageClient.defaultUserAgent,
        endpoint: URL = OpenCodeGoUsageClient.defaultEndpoint
    ) {
        self.http = http
        self.userAgent = userAgent
        self.endpoint = endpoint
    }

    public func fetch(_ credential: OpenCodeCredential) async throws(ProviderError) -> HTTPResponse {
        let request = HTTPRequest(url: endpoint, headers: [
            "Authorization": "Bearer \(credential.key)",
            "Accept": "application/json",
            "User-Agent": userAgent,
        ])
        let response = try await http.send(request)
        if let error = response.providerError {
            throw error
        }
        return response
    }
}
