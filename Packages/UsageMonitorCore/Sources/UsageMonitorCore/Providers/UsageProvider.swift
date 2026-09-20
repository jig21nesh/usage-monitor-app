import Foundation

/// One vendor adapter. Implementations are value types holding only Sendable collaborators
/// (ADR 0001): a `CredentialSource`, an `HTTPClient` and a pure mapper.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Inspects the credential store only. Must not touch the network.
    func linkState() async -> LinkState

    /// Performs exactly one read-only request and maps it to a snapshot.
    func fetchUsage() async throws(ProviderError) -> UsageSnapshot

    /// A floor on how often this provider may be polled, regardless of the user's refresh
    /// interval or a forced refresh. Nil means no floor (ADR 0003).
    var minimumPollInterval: Duration? { get }
}

extension UsageProvider {
    public var minimumPollInterval: Duration? { nil }
}
