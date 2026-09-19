import Foundation

/// One read-only request to the billing endpoint the Grok Build CLI itself uses (ADR 0003).
public struct GrokUsageClient: Sendable {
    public static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    /// The proxy gates chat routes on the CLI version and may do the same for billing; keep this
    /// in step with the released Grok Build CLI.
    public static let defaultClientVersion = "1.0.13"
    public static let tokenAuthHeaderValue = "xai-grok-cli"
    public static let userAgent = "AIUsageMonitor/0.1.0 (macOS)"

    let http: any HTTPClient
    let clientVersion: String

    public init(http: any HTTPClient, clientVersion: String = GrokUsageClient.defaultClientVersion) {
        self.http = http
        self.clientVersion = clientVersion
    }

    public func fetchBilling(with credential: GrokCredential) async throws(ProviderError) -> Data {
        let response = try await http.send(request(for: credential))
        if let error = response.providerError {
            throw error
        }
        return response.body
    }

    func request(for credential: GrokCredential) -> HTTPRequest {
        var headers = [
            "Authorization": "Bearer \(credential.accessToken)",
            "X-XAI-Token-Auth": Self.tokenAuthHeaderValue,
            "Accept": "application/json",
            "x-grok-client-version": clientVersion,
            "User-Agent": Self.userAgent,
        ]
        if let userID = credential.userID, !userID.isEmpty {
            headers["x-userid"] = userID
        }
        return HTTPRequest(url: Self.endpoint, headers: headers)
    }
}
