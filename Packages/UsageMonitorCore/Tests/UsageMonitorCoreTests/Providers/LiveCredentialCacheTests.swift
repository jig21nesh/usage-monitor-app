import Foundation
import Synchronization
import Testing
@testable import UsageMonitorCore

/// Counts keychain reads so the tests can prove a live provider reads an item once per launch.
private final class CountingKeychainReader: KeychainReader, Sendable {
    let reads = CallCounter()
    private let items: [String: Data]

    init(items: [String: Data]) {
        self.items = items
    }

    func genericPassword(service: String, account: String?) throws(KeychainReadError) -> Data? {
        reads.increment()
        return items[service]
    }
}

/// The live factories wrap every credential source in `CachedCredentialSource` (ADR 0002
/// amendment 2026-09-21); these tests pin that wiring for the two keychain-backed providers
/// whose consent dialogs prompted the change.
@Suite("Live providers cache credentials")
struct LiveCredentialCacheTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let environment = UserEnvironment(homeDirectory: URL(filePath: "/nonexistent", directoryHint: .isDirectory))

    private func claudeItem(expiresAt: Date) -> Data {
        let millis = Int(expiresAt.timeIntervalSince1970 * 1000)
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-test","expiresAt":\(millis),"scopes":["user:inference"],\
        "subscriptionType":"max"}}
        """
        return Data(json.utf8)
    }

    private func claude(keychain: CountingKeychainReader, now: @escaping @Sendable () -> Date) -> ClaudeUsageProvider {
        ClaudeUsageProvider.live(
            environment: environment, http: FakeHTTPClient(), keychain: keychain, fileSystem: FakeFileSystem(), now: now
        )
    }

    @Test func claudeReadsTheKeychainOncePerLaunchAndAgainAfterForget() async {
        let item = claudeItem(expiresAt: start.addingTimeInterval(8 * 3600))
        let keychain = CountingKeychainReader(items: [ClaudeCodeCredentialSource.keychainService: item])
        let provider = claude(keychain: keychain, now: { [start] in start })

        let first = await provider.linkState()
        let second = await provider.linkState()

        #expect(first.isLinked)
        #expect(second == first)
        #expect(keychain.reads.total == 1)

        provider.forgetCredentials()
        _ = await provider.linkState()
        #expect(keychain.reads.total == 2)
    }

    @Test func claudeReadsTheKeychainAgainWhenTheTokenNearsExpiry() async {
        let clock = Mutex(start)
        let item = claudeItem(expiresAt: start.addingTimeInterval(600))
        let keychain = CountingKeychainReader(items: [ClaudeCodeCredentialSource.keychainService: item])
        let provider = claude(keychain: keychain, now: { clock.withLock { $0 } })

        _ = await provider.linkState()
        clock.withLock { $0 = start.addingTimeInterval(300) }
        _ = await provider.linkState()
        #expect(keychain.reads.total == 1)

        clock.withLock { $0 = start.addingTimeInterval(541) }
        _ = await provider.linkState()
        #expect(keychain.reads.total == 2)
    }

    @Test func claudeMissingItemIsAskedAgainOnEveryProbe() async {
        // Nothing to cache, so a later `claude login` is noticed at the next probe.
        let keychain = CountingKeychainReader(items: [:])
        let provider = claude(keychain: keychain, now: { [start] in start })

        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        #expect(keychain.reads.total == 2)
    }

    @Test func copilotReadsTheKeychainOncePerLaunchAndAgainAfterForget() async {
        let keychain = CountingKeychainReader(items: [CopilotCredentialSource.ghKeychainService: Data("gho_test".utf8)])
        let provider = CopilotUsageProvider.live(
            environment: environment,
            http: FakeHTTPClient(),
            keychain: keychain,
            fileSystem: FakeFileSystem(),
            now: { [start] in start }
        )

        let first = await provider.linkState()
        _ = await provider.linkState()
        #expect(first.isLinked)
        #expect(keychain.reads.total == 1)

        provider.forgetCredentials()
        _ = await provider.linkState()
        #expect(keychain.reads.total == 2)
    }
}
