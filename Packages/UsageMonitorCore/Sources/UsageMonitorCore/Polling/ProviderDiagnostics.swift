import Foundation

/// Local-only counters surfaced in the Diagnostics pane (ADR 0006).
public struct ProviderDiagnostics: Sendable, Hashable, Codable {
    public var polls = 0
    public var successes = 0
    public var failures = 0
    public var lastDuration: Duration?
    public var lastSuccessAt: Date?
    public var lastErrorIdentifier: String?

    public init() {}
}
