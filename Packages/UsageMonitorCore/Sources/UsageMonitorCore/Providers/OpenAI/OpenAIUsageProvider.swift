import Foundation

/// Scaffold placeholder so the app runs end to end showing "not linked". Replaced by the
/// provider implementation branch; the `live` signature is the contract that branch fulfils.
public struct OpenAIUsageProvider: UsageProvider {
    public let id: ProviderID = .openAI

    public init() {}

    public static func live(
        environment: UserEnvironment,
        http: any HTTPClient,
        keychain: any KeychainReader,
        fileSystem: any FileSystem,
        now: @escaping @Sendable () -> Date
    ) -> OpenAIUsageProvider {
        OpenAIUsageProvider()
    }

    public func linkState() async -> LinkState {
        .notLinked(.credentialsNotFound)
    }

    public func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        throw .credentialsNotFound
    }
}
