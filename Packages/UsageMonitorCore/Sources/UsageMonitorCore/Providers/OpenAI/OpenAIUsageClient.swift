import Foundation

/// One read-only request to the endpoint the Codex CLI itself polls (ADR 0003).
public struct OpenAIUsageClient: Sendable {
    public static let defaultUserAgent = "AIUsageMonitor/0.1.0 (macOS)"

    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            preconditionFailure("constant endpoint URL is valid")
        }
        return url
    }()

    private let http: any HTTPClient
    private let userAgent: String
    private let endpoint: URL

    public init(
        http: any HTTPClient,
        userAgent: String = OpenAIUsageClient.defaultUserAgent,
        endpoint: URL = OpenAIUsageClient.defaultEndpoint
    ) {
        self.http = http
        self.userAgent = userAgent
        self.endpoint = endpoint
    }

    public func fetch(_ credential: OpenAICredential) async throws(ProviderError) -> HTTPResponse {
        var headers = [
            "Authorization": "Bearer \(credential.accessToken)",
            "Accept": "application/json",
            "User-Agent": userAgent,
        ]
        if let accountID = credential.accountID {
            headers["ChatGPT-Account-Id"] = accountID
        } else {
            UsageLog.providers.debug("openai request without account id")
        }
        let response = try await http.send(HTTPRequest(url: endpoint, headers: headers))
        if let error = response.providerError {
            throw error
        }
        return response
    }
}
