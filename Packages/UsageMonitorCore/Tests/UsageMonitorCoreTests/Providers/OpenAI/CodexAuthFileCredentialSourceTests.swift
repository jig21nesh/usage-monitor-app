import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CodexAuthFileCredentialSource")
struct CodexAuthFileCredentialSourceTests {
    typealias Support = OpenAITestSupport

    @Test func readsTokenAccountAndClaims() throws {
        let idToken = Support.jwt(
            auth: ["chatgpt_account_id": "acct_jwt", "chatgpt_plan_type": "pro"],
            profile: ["email": "me@example.com"]
        )
        let source = Support.makeSource(contents: Support.authFile(idToken: idToken))
        let credential = try source.load()
        #expect(credential.accessToken == "access-token-value")
        #expect(credential.accountID == "acct_file")
        #expect(credential.planType == "pro")
        #expect(credential.email == "me@example.com")
    }

    @Test func fallsBackToJWTAccountIDWhenFileHasNone() throws {
        let idToken = Support.jwt(auth: ["chatgpt_account_id": "acct_jwt", "chatgpt_plan_type": "plus"])
        let source = Support.makeSource(contents: Support.authFile(accountID: nil, idToken: idToken))
        let credential = try source.load()
        #expect(credential.accountID == "acct_jwt")
        #expect(credential.planType == "plus")
        #expect(credential.email == nil)
    }

    @Test func blankFileAccountIDIsTreatedAsMissing() throws {
        let idToken = Support.jwt(auth: ["chatgpt_account_id": "acct_jwt"])
        let source = Support.makeSource(contents: Support.authFile(accountID: "  ", idToken: idToken))
        #expect(try source.load().accountID == "acct_jwt")
    }

    @Test(arguments: ["not.a.jwt", "onlyone", "h.!!!.s", ""])
    func malformedIDTokenIsNonFatal(idToken: String) throws {
        let source = Support.makeSource(contents: Support.authFile(idToken: idToken))
        let credential = try source.load()
        #expect(credential.accessToken == "access-token-value")
        #expect(credential.accountID == "acct_file")
        #expect(credential.planType == nil)
        #expect(credential.email == nil)
    }

    @Test func noIDTokenLeavesClaimsNil() throws {
        let credential = try Support.makeSource(contents: Support.authFile()).load()
        #expect(credential.planType == nil)
        #expect(credential.email == nil)
        #expect(credential.accountID == "acct_file")
    }

    @Test func apiKeyOnlyLoginIsNotLinked() {
        let source = Support.makeSource(contents: Support.authFile(includeTokens: false, apiKey: "sk-test-key"))
        #expect(throws: ProviderError.credentialsNotFound) { try source.load() }
    }

    @Test(arguments: [nil, "", "   "])
    func missingOrBlankAccessTokenIsNotLinked(token: String?) {
        let source = Support.makeSource(contents: Support.authFile(accessToken: token))
        #expect(throws: ProviderError.credentialsNotFound) { try source.load() }
    }

    @Test func missingFileIsNotLinked() {
        #expect(throws: ProviderError.credentialsNotFound) { try Support.makeSource(contents: nil).load() }
    }

    @Test func malformedJSONIsReported() {
        let source = Support.makeSource(contents: "{\"tokens\": ")
        #expect(throws: ProviderError.credentialsMalformed("codex_json")) { try source.load() }
    }

    @Test func oversizedFileIsRejected() {
        let source = Support.makeSource(contents: nil, rawData: Data(repeating: 0x20, count: 70_000))
        #expect(throws: ProviderError.credentialsMalformed("codex_file_size")) { try source.load() }
    }

    @Test func unreadableFileIsReported() {
        let source = Support.makeSource(contents: nil, unreadable: true)
        #expect(throws: ProviderError.credentialsUnreadable("codex_file")) { try source.load() }
    }

    @Test func defaultPathIsUnderHome() {
        let source = Support.makeSource(contents: nil)
        #expect(source.fileURL.path(percentEncoded: false) == "/Users/tester/.codex/auth.json")
    }

    @Test func honoursAbsoluteCodexHomeOverride() throws {
        let source = Support.makeSource(contents: Support.authFile(), variables: ["CODEX_HOME": "/opt/codex"])
        #expect(source.fileURL.path(percentEncoded: false) == "/opt/codex/auth.json")
        #expect(try source.load().accessToken == "access-token-value")
    }

    @Test func ignoresRelativeCodexHomeOverride() {
        let source = Support.makeSource(contents: Support.authFile(), variables: ["CODEX_HOME": "relative/codex"])
        #expect(source.fileURL.path(percentEncoded: false) == "/Users/tester/.codex/auth.json")
    }

    @Test func refreshTokenIsNeverExposed() throws {
        let credential = try Support.makeSource(contents: Support.authFile()).load()
        #expect(!String(describing: credential).contains("refresh-token-value"))
    }
}
