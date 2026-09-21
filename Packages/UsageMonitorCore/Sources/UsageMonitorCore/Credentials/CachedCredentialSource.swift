import Foundation
import Synchronization

/// Keeps the last credential a source returned in process memory so the vendor's store is read
/// again only when it has to be (ADR 0002, amendment 2026-09-21).
///
/// Why: reading another tool's keychain item can show a macOS consent dialog, and a one-shot
/// "Allow" would otherwise come back on every poll. The credential lives only in this object;
/// nothing is written to disk, `UserDefaults`, the keychain or the log.
public final class CachedCredentialSource<Base: CredentialSource>: CredentialSource, Sendable {
    public typealias Credential = Base.Credential

    /// A credential this close to its expiry is re-read instead of being handed out.
    public static var defaultGrace: TimeInterval { 60 }

    private enum Slot {
        case cold
        case forgotten
        case cached(Credential)
    }

    private let base: Base
    private let label: String
    private let expiry: @Sendable (Credential) -> Date?
    private let now: @Sendable () -> Date
    private let grace: TimeInterval
    private let slot = Mutex<Slot>(.cold)

    /// - Parameters:
    ///   - label: appears in the log line for a cache miss; use the provider id, never the account.
    ///   - expiry: the credential's own expiry, or nil for tokens that carry none.
    public init(
        _ base: Base,
        label: String,
        expiry: @escaping @Sendable (Credential) -> Date?,
        now: @escaping @Sendable () -> Date,
        grace: TimeInterval = CachedCredentialSource.defaultGrace
    ) {
        self.base = base
        self.label = label
        self.expiry = expiry
        self.now = now
        self.grace = grace
    }

    /// Serialised under the lock so concurrent callers never trigger two store reads, and so
    /// two consent dialogs never appear for the same item.
    public func load() throws(ProviderError) -> Credential {
        try slot.withLock { (slot: inout Slot) throws(ProviderError) -> Credential in
            let reason: String
            switch slot {
            case .cached(let credential) where !isNearExpiry(credential):
                return credential
            case .cached:
                reason = "expired"
            case .cold:
                reason = "cold"
            case .forgotten:
                reason = "forgotten"
            }
            UsageLog.credentials.info(
                "credential cache miss provider=\(self.label, privacy: .public) reason=\(reason, privacy: .public)"
            )
            let credential = try base.load()
            slot = .cached(credential)
            return credential
        }
    }

    /// Drops the cached credential so the next `load()` reads the store again.
    public func forget() {
        slot.withLock { $0 = .forgotten }
    }

    private func isNearExpiry(_ credential: Credential) -> Bool {
        guard let expiresAt = expiry(credential) else { return false }
        return expiresAt.timeIntervalSince(now()) <= grace
    }
}
