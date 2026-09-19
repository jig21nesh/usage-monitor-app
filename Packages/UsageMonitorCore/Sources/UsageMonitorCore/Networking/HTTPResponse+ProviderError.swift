import Foundation

extension HTTPResponse {
    /// Shared status handling for every vendor endpoint (ADR 0003). Nil means success.
    public var providerError: ProviderError? {
        switch statusCode {
        case 200..<300: nil
        case 401, 403: .unauthorized(status: statusCode)
        case 426: .clientOutdated
        case 429: .rateLimited(retryAfter: retryAfterSeconds)
        case 500..<600: .serverError(status: statusCode)
        default: .unexpectedStatus(statusCode)
        }
    }
}
