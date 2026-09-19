import Foundation

/// One read-only GET against the usage endpoint Claude Code's own `/usage` command uses (ADR 0003).
public struct ClaudeUsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"
    /// Claude Code version advertised in the User-Agent. The endpoint keys its lenient rate-limit
    /// bucket on Claude Code's agent string; other agents get persistent 429s (ADR 0003, measured
    /// 2026-09-19 at 60-second polling).
    public static let defaultClientVersion = "2.1.277"

    private let http: any HTTPClient
    private let clientVersion: String

    public init(http: any HTTPClient, clientVersion: String = ClaudeUsageClient.defaultClientVersion) {
        self.http = http
        self.clientVersion = clientVersion
    }

    public var userAgent: String { "claude-cli/\(clientVersion) (external, cli)" }

    /// Returns the validated 2xx response; every other status becomes a `ProviderError`.
    public func fetchUsage(token: String) async throws(ProviderError) -> HTTPResponse {
        let request = HTTPRequest(url: Self.endpoint, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": Self.betaHeader,
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
