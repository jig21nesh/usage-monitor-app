import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ClaudeCodeCredentialSource")
struct ClaudeCodeCredentialSourceTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    private func makeSource(
        keychain: FakeKeychainReader = FakeKeychainReader(),
        variables: [String: String] = [:]
    ) -> ClaudeCodeCredentialSource {
        let fixedNow = now
        return ClaudeCodeCredentialSource(
            keychain: keychain,
            environment: UserEnvironment(homeDirectory: home, variables: variables),
            now: { fixedNow }
        )
    }

    private func keychain(with data: Data) -> FakeKeychainReader {
        FakeKeychainReader(items: [ClaudeCodeCredentialSource.keychainService: data])
    }

    private func keychain(json: String) -> FakeKeychainReader {
        keychain(with: Data(json.utf8))
    }

    @Test func validItemLoadsTokenPlanExpiryAndScopes() throws {
        let data = try Fixtures.data("keychain-item-valid", subdirectory: "claude")
        let credential = try makeSource(keychain: keychain(with: data)).load()

        #expect(credential.accessToken == "sk-ant-oat01-FIXTURE-TOKEN-NOT-REAL")
        #expect(credential.subscriptionType == "max")
        #expect(credential.rateLimitTier == "default_claude_max_20x")
        #expect(credential.planName == "Max (20x)")
        #expect(credential.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(credential.scopes == ["user:inference", "user:profile", "org:create_api_key"])
    }

    @Test func itemWithOnlyMcpOAuthIsNotFound() throws {
        let data = try Fixtures.data("keychain-item-mcp-only", subdirectory: "claude")
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource(keychain: keychain(with: data)).load()
        }
    }

    @Test func missingItemAndNoEnvironmentVariableIsNotFound() {
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource().load()
        }
    }

    @Test func environmentVariableIsTheFallbackWithoutMetadata() throws {
        let variables = [ClaudeCodeCredentialSource.tokenEnvironmentVariable: "  sk-ant-oat01-env  "]
        let credential = try makeSource(variables: variables).load()
        #expect(credential.accessToken == "sk-ant-oat01-env")
        #expect(credential.planName == nil)
        #expect(credential.expiresAt == nil)
        #expect(credential.scopes.isEmpty)
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankEnvironmentVariableIsIgnored(value: String) {
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource(variables: [ClaudeCodeCredentialSource.tokenEnvironmentVariable: value]).load()
        }
    }

    @Test func keychainItemTakesPrecedenceOverEnvironment() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-keychain","subscriptionType":"pro"}}"#
        let source = makeSource(
            keychain: keychain(json: json),
            variables: [ClaudeCodeCredentialSource.tokenEnvironmentVariable: "sk-ant-oat01-env"]
        )
        let credential = try source.load()
        #expect(credential.accessToken == "sk-ant-oat01-keychain")
        #expect(credential.planName == "Pro")
    }

    @Test func blankTokenInItemFallsThroughToEnvironment() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"   "}}"#
        let source = makeSource(
            keychain: keychain(json: json),
            variables: [ClaudeCodeCredentialSource.tokenEnvironmentVariable: "sk-ant-oat01-env"]
        )
        #expect(try source.load().accessToken == "sk-ant-oat01-env")
    }

    @Test(arguments: ["not json", "[1,2]", #"{"claudeAiOauth":"nope"}"#, #"{"claudeAiOauth":{"expiresAt":"soon"}}"#])
    func malformedItemsAreReported(json: String) {
        #expect(throws: ProviderError.credentialsMalformed("claude_json")) {
            try makeSource(keychain: keychain(json: json)).load()
        }
    }

    @Test func oversizedItemIsRejected() {
        let huge = Data(repeating: 0x20, count: ClaudeCodeCredentialSource.maxItemBytes + 1)
        #expect(throws: ProviderError.credentialsMalformed("claude_json_too_large")) {
            try makeSource(keychain: keychain(with: huge)).load()
        }
    }

    @Test func expiredTokenIsReportedAsExpired() {
        let past = Int((now.timeIntervalSince1970 - 60) * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-old","expiresAt":\#(past)}}"#
        #expect(throws: ProviderError.credentialsExpired) {
            try makeSource(keychain: keychain(json: json)).load()
        }
    }

    @Test func tokenExpiringExactlyNowIsExpired() {
        let exact = Int(now.timeIntervalSince1970 * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-old","expiresAt":\#(exact)}}"#
        #expect(throws: ProviderError.credentialsExpired) {
            try makeSource(keychain: keychain(json: json)).load()
        }
    }

    @Test func expiryInSecondsIsAlsoUnderstood() throws {
        let future = Int(now.timeIntervalSince1970 + 3600)
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-ok","expiresAt":\#(future)}}"#
        let credential = try makeSource(keychain: keychain(json: json)).load()
        #expect(credential.expiresAt == now.addingTimeInterval(3600))
    }

    @Test func missingExpiryIsAccepted() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-ok","subscriptionType":"max"}}"#
        let credential = try makeSource(keychain: keychain(json: json)).load()
        #expect(credential.expiresAt == nil)
        #expect(credential.planName == "Max")
        #expect(credential.scopes.isEmpty)
    }

    @Test(arguments: [
        (KeychainReadError.interactionRequired, "keychain_interaction_required"),
        (KeychainReadError.accessDenied(status: -34018), "keychain_access_denied"),
        (KeychainReadError.unexpectedStatus(-1), "keychain_unexpected_status"),
    ])
    func keychainFailuresAreUnreadable(error: KeychainReadError, reason: String) {
        let reader = FakeKeychainReader(items: [:], error: error)
        #expect(throws: ProviderError.credentialsUnreadable(reason)) {
            try makeSource(keychain: reader).load()
        }
    }

    @Test func keychainFailureIsNotMaskedByEnvironmentFallback() {
        let reader = FakeKeychainReader(items: [:], error: .interactionRequired)
        let source = makeSource(
            keychain: reader,
            variables: [ClaudeCodeCredentialSource.tokenEnvironmentVariable: "sk-ant-oat01-env"]
        )
        #expect(throws: ProviderError.credentialsUnreadable("keychain_interaction_required")) {
            try source.load()
        }
    }

    @Test(arguments: [
        ("max", "default_claude_max_20x", "Max (20x)"),
        ("MAX", "claude_max_5x", "Max (5x)"),
        ("max", nil, "Max"),
        ("pro", "default_pro", "Pro"),
        ("team", nil, "Team"),
        ("enterprise", nil, "Enterprise"),
        ("free", nil, "Free"),
    ])
    func planNameDerivation(subscription: String, tier: String?, expected: String) {
        let credential = ClaudeCredential(
            accessToken: "t", subscriptionType: subscription, rateLimitTier: tier, expiresAt: nil, scopes: []
        )
        #expect(credential.planName == expected)
    }

    @Test(arguments: [nil, "", "   "])
    func unknownSubscriptionHasNoPlanName(subscription: String?) {
        let credential = ClaudeCredential(
            accessToken: "t", subscriptionType: subscription, rateLimitTier: "x", expiresAt: nil, scopes: []
        )
        #expect(credential.planName == nil)
    }

    @Test func descriptionsNeverContainTheToken() {
        let credential = ClaudeCredential(
            accessToken: "sk-ant-oat01-SECRETSECRET", subscriptionType: "max", rateLimitTier: nil,
            expiresAt: now, scopes: ["user:profile"]
        )
        #expect(!credential.description.contains("SECRET"))
        #expect(!credential.debugDescription.contains("SECRET"))
        #expect(!String(describing: credential).contains("SECRET"))
        #expect(!String(reflecting: credential).contains("SECRET"))
        #expect(credential.description.contains("<redacted>"))
    }
}
