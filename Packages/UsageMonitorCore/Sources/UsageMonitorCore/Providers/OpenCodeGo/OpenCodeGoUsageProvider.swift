import Foundation

/// Placeholder so the app runs end to end showing "not linked" until the provider branch lands.
/// The `live` signature is the contract that branch fulfils (ADR 0008).
public struct OpenCodeGoUsageProvider: UsageProvider {
    public let id: ProviderID = .opencodeGo

    public init() {}

    public static func live(
        environment: UserEnvironment,
        http: any HTTPClient,
        keychain: any KeychainReader,
        fileSystem: any FileSystem,
        now: @escaping @Sendable () -> Date
    ) -> OpenCodeGoUsageProvider {
        OpenCodeGoUsageProvider()
    }

    public func linkState() async -> LinkState {
        .notLinked(.credentialsNotFound)
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        throw .credentialsNotFound
    }
}
