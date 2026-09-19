import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ProviderID")
struct ProviderIDTests {
    @Test func rawValuesArePersistedAndMustStayStable() {
        #expect(ProviderID.claude.rawValue == "claude")
        #expect(ProviderID.openAI.rawValue == "openai")
        #expect(ProviderID.grok.rawValue == "grok")
        #expect(ProviderID.allCases == [.claude, .openAI, .grok])
    }

    @Test(arguments: ProviderID.allCases)
    func everyProviderHasUserFacingText(id: ProviderID) {
        #expect(!id.displayName.isEmpty)
        #expect(!id.credentialOrigin.isEmpty)
        #expect(id.loginCommand.hasSuffix(" login"))
        #expect(id.id == id.rawValue)
    }

    @Test func onlyGrokIsExperimental() {
        #expect(ProviderID.allCases.filter(\.isExperimental) == [.grok])
    }
}

@Suite("ProviderError")
struct ProviderErrorTests {
    static let allCases: [ProviderError] = [
        .credentialsNotFound, .credentialsUnreadable("x"), .credentialsMalformed("y"), .credentialsExpired,
        .unauthorized(status: 401), .rateLimited(retryAfter: 30), .clientOutdated, .network("n"),
        .serverError(status: 503), .unexpectedStatus(418), .responseTooLarge(limit: 1), .decoding("d"), .cancelled,
    ]

    @Test(arguments: allCases)
    func everyCaseHasMessageAndIdentifier(error: ProviderError) {
        #expect(!error.userMessage.isEmpty)
        #expect(!error.logIdentifier.isEmpty)
        #expect(!error.logIdentifier.contains(" "))
    }

    @Test func relinkClassification() {
        let relink: [ProviderError] = [
            .credentialsNotFound, .credentialsUnreadable("x"), .credentialsMalformed("y"),
            .credentialsExpired, .unauthorized(status: 403),
        ]
        let transient: [ProviderError] = [
            .rateLimited(retryAfter: nil), .clientOutdated, .network("n"), .serverError(status: 500),
            .unexpectedStatus(418), .responseTooLarge(limit: 1), .decoding("d"), .cancelled,
        ]
        let allRelink = relink.allSatisfy { $0.requiresRelink }
        let anyTransientRelink = transient.contains { $0.requiresRelink }
        #expect(allRelink)
        #expect(!anyTransientRelink)
    }

    @Test func retryAfterHintOnlyForRateLimits() {
        #expect(ProviderError.rateLimited(retryAfter: 42).retryAfterHint == 42)
        #expect(ProviderError.rateLimited(retryAfter: nil).retryAfterHint == nil)
        #expect(ProviderError.serverError(status: 503).retryAfterHint == nil)
    }

    @Test func identifiersCarryStatusCodesButNoPayloadText() {
        #expect(ProviderError.unauthorized(status: 401).logIdentifier == "unauthorized:401")
        #expect(ProviderError.serverError(status: 502).logIdentifier == "server_error:502")
        #expect(ProviderError.rateLimited(retryAfter: 99).logIdentifier == "rate_limited")
    }
}

@Suite("ProviderStatus and LinkState")
struct ProviderStatusTests {
    @Test func staleOnlyWhenSnapshotAndErrorCoexist() {
        var status = ProviderStatus(provider: .claude, isEnabled: true)
        #expect(!status.isStale)
        status.lastError = .network("x")
        #expect(!status.isStale)
        status.snapshot = .sample(provider: .claude)
        #expect(status.isStale)
        status.lastError = nil
        #expect(!status.isStale)
        #expect(status.id == .claude)
    }

    @Test func linkStateHelpers() {
        let info = AccountInfo(planName: "Max", accountLabel: nil, origin: "Claude Code")
        #expect(LinkState.linked(info).account == info)
        #expect(LinkState.linked(info).isLinked)
        #expect(LinkState.unknown.account == nil)
        #expect(!LinkState.notLinked(.credentialsNotFound).isLinked)
    }
}
