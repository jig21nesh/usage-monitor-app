import Foundation

/// One read-only request to the endpoint GitHub's own editor integrations use for quota (ADR 0008).
public struct CopilotUsageClient: Sendable {
    public static let defaultUserAgent = "AIUsageMonitor/0.1.0 (macOS)"

    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            preconditionFailure("constant endpoint URL is valid")
        }
        return url
    }()

    private let http: any HTTPClient
    private let userAgent: String
    private let endpoint: URL

    public init(
        http: any HTTPClient,
        userAgent: String = CopilotUsageClient.defaultUserAgent,
        endpoint: URL = CopilotUsageClient.defaultEndpoint
    ) {
        self.http = http
        self.userAgent = userAgent
        self.endpoint = endpoint
    }

    public func fetch(_ credential: CopilotCredential) async throws(ProviderError) -> HTTPResponse {
        let request = HTTPRequest(url: endpoint, headers: [
            "Authorization": "token \(credential.token)",
            "Accept": "application/json",
            "User-Agent": userAgent,
        ])
        let response = try await http.send(request)
        // GitHub answers 404 for accounts without a Copilot seat; for this app that is the same
        // as a rejected login: the user must fix it on GitHub's side, not by retrying.
        if response.statusCode == 404 {
            throw .unauthorized(status: 404)
        }
        if let error = response.providerError {
            throw error
        }
        return response
    }
}
