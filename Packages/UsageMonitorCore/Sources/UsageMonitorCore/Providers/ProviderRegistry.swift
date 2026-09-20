import Foundation

/// Composition root for the production providers. Views never call this; the app target does once.
public enum ProviderRegistry {
    public static func live(
        environment: UserEnvironment = .current(),
        http: any HTTPClient = URLSessionHTTPClient(),
        keychain: any KeychainReader = SecurityFrameworkKeychainReader(),
        fileSystem: any FileSystem = LocalFileSystem(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> [any UsageProvider] {
        [
            ClaudeUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            OpenAIUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            GrokUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            CopilotUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            CursorUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            MuseUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
            OpenCodeGoUsageProvider.live(
                environment: environment, http: http, keychain: keychain, fileSystem: fileSystem, now: now
            ),
        ]
    }
}
