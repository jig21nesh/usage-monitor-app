import Foundation

/// Reads a vendor CLI's stored login at call time. Implementations must never cache the
/// credential beyond the call and must never write anything (ADR 0002).
public protocol CredentialSource<Credential>: Sendable {
    associatedtype Credential: Sendable

    func load() throws(ProviderError) -> Credential
}
