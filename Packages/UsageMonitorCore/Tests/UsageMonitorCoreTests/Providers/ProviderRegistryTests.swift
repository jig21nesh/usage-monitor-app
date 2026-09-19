import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    private func makeProviders() -> [any UsageProvider] {
        ProviderRegistry.live(
            environment: UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory)),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    @Test func liveRegistryListsEveryProviderInDisplayOrder() {
        #expect(makeProviders().map(\.id) == [.claude, .openAI, .grok])
    }

    @Test func providersWithoutAnyCredentialStoreReportNotLinked() async {
        for provider in makeProviders() {
            #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
            await #expect(throws: ProviderError.credentialsNotFound) {
                try await provider.fetchUsage()
            }
        }
    }
}
