import Foundation

/// Reads a vendor CLI's stored login. A source may hold the credential in process memory
/// between calls (see `CachedCredentialSource`) but must never write it anywhere and must never
/// refresh it (ADR 0002).
public protocol CredentialSource<Credential>: Sendable {
    associatedtype Credential: Sendable

    func load() throws(ProviderError) -> Credential

    /// Drops anything held in memory so the next `load()` reads the store again. Sources that
    /// hold nothing between calls do nothing.
    func forget()
}

extension CredentialSource {
    public func forget() {}
}
