import Foundation

/// One request to the dashboard RPC Cursor's own settings page calls. It is a POST because the
/// Connect service only accepts POST, but it reads state and changes nothing (ADR 0003 amendment).
public struct CursorUsageClient: Sendable {
    public static let defaultEndpoint: URL = {
        let text = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
        guard let url = URL(string: text) else {
            preconditionFailure("constant endpoint URL is valid")
        }
        return url
    }()
    public static let defaultUserAgent = "AIUsageMonitor/0.1.0 (macOS)"
    static let emptyBody = Data("{}".utf8)

    private let http: any HTTPClient
    private let endpoint: URL
    private let userAgent: String

    public init(
        http: any HTTPClient,
        endpoint: URL = CursorUsageClient.defaultEndpoint,
        userAgent: String = CursorUsageClient.defaultUserAgent
    ) {
        self.http = http
        self.endpoint = endpoint
        self.userAgent = userAgent
    }

    public func fetchCurrentPeriodUsage(token: String) async throws(ProviderError) -> HTTPResponse {
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Connect-Protocol-Version": "1",
                "User-Agent": userAgent,
            ],
            body: Self.emptyBody
        )
        let response = try await http.send(request)
        if let error = response.providerError {
            throw error
        }
        return response
    }
}
