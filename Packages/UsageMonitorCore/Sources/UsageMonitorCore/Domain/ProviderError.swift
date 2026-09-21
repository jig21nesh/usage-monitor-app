import Foundation

/// Every failure a provider can surface. Associated `String` values are fixed identifiers,
/// never vendor content or credential material, so the whole enum is safe to log.
public enum ProviderError: Error, Sendable, Hashable {
    case credentialsNotFound
    case credentialsUnreadable(String)
    case credentialsMalformed(String)
    case credentialsExpired
    case unauthorized(status: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case clientOutdated
    case network(String)
    case serverError(status: Int)
    case unexpectedStatus(Int)
    case responseTooLarge(limit: Int)
    case decoding(String)
    case cancelled

    /// Reason carried by `credentialsUnreadable` when the home folder grant is missing (ADR 0009).
    public static let homeFolderNotGranted = "home_folder_not_granted"

    /// True when the fix is on the user's side: log in to the vendor CLI again and re-link.
    public var requiresRelink: Bool {
        switch self {
        case .credentialsNotFound, .credentialsUnreadable, .credentialsMalformed, .credentialsExpired, .unauthorized:
            true
        default:
            false
        }
    }

    public var retryAfterHint: TimeInterval? {
        if case .rateLimited(let retryAfter) = self { return retryAfter }
        return nil
    }

    /// Stable, payload-free identifier for logs and diagnostics.
    public var logIdentifier: String {
        switch self {
        case .credentialsNotFound: "credentials_not_found"
        case .credentialsUnreadable(let reason): "credentials_unreadable:\(reason)"
        case .credentialsMalformed(let reason): "credentials_malformed:\(reason)"
        case .credentialsExpired: "credentials_expired"
        case .unauthorized(let status): "unauthorized:\(status)"
        case .rateLimited: "rate_limited"
        case .clientOutdated: "client_outdated"
        case .network(let code): "network:\(code)"
        case .serverError(let status): "server_error:\(status)"
        case .unexpectedStatus(let status): "unexpected_status:\(status)"
        case .responseTooLarge: "response_too_large"
        case .decoding(let reason): "decoding:\(reason)"
        case .cancelled: "cancelled"
        }
    }

    public var userMessage: String {
        switch self {
        case .credentialsNotFound: "No login found. Sign in with the vendor CLI, then link."
        case .credentialsUnreadable(Self.homeFolderNotGranted):
            "Grant access to your home folder in the Welcome window or Settings > Accounts."
        case .credentialsUnreadable: "The stored login could not be read."
        case .credentialsMalformed: "The stored login has an unexpected format."
        case .credentialsExpired: "The stored login has expired. Sign in with the CLI again."
        case .unauthorized: "The vendor rejected the stored login. Sign in with the CLI again."
        case .rateLimited: "Rate limited by the vendor. Retrying later."
        case .clientOutdated: "The vendor requires a newer client. Update the app."
        case .network: "Network error. Will retry."
        case .serverError: "The vendor service returned an error. Will retry."
        case .unexpectedStatus: "Unexpected response from the vendor."
        case .responseTooLarge: "The vendor response was too large to process."
        case .decoding: "The vendor response could not be understood."
        case .cancelled: "Cancelled."
        }
    }
}
