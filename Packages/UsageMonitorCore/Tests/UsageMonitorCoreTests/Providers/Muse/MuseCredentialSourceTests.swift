import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("MuseCredentialSource")
struct MuseCredentialSourceTests {
    typealias Support = MuseTestSupport

    @Test func inlineTokenInFileWins() throws {
        let source = Support.source(
            file: Support.authFile(email: "dev@example.com"),
            keychainJSON: #"{"access_token":"dca:from-keychain"}"#
        )
        let credential = try source.load()
        #expect(credential.accessToken == Support.token)
        #expect(credential.email == "dev@example.com")
    }

    @Test func fileConfiguredForKeychainReadsTopLevelKeychainToken() throws {
        let source = Support.source(
            file: Support.authFile(token: nil, email: "hint@example.com", storage: "keychain"),
            keychainJSON: #"{"access_token":"dca:from-keychain"}"#
        )
        let credential = try source.load()
        #expect(credential.accessToken == "dca:from-keychain")
        #expect(credential.email == "hint@example.com")
    }

    @Test func missingFileReadsNestedKeychainToken() throws {
        let json = #"{"providers":{"meta":{"access_token":"dca:nested","email":"kc@example.com"}}}"#
        let credential = try Support.source(keychainJSON: json).load()
        #expect(credential.accessToken == "dca:nested")
        #expect(credential.email == "kc@example.com")
    }

    @Test func nothingStoredAnywhereIsNotFound() {
        #expect(throws: ProviderError.credentialsNotFound) { try Support.source().load() }
        let tokenless = Support.source(file: Support.authFile(token: nil), keychainJSON: #"{"other":1}"#)
        #expect(throws: ProviderError.credentialsNotFound) { try tokenless.load() }
    }

    @Test func apiKeysAreRejectedBeforeAnyRequest() {
        #expect(throws: ProviderError.credentialsMalformed("muse_token_kind")) {
            try Support.source(file: Support.authFile(token: "LLM|123|abc")).load()
        }
        #expect(throws: ProviderError.credentialsMalformed("muse_token_kind")) {
            try Support.source(keychainJSON: #"{"access_token":"LLM|123|abc"}"#).load()
        }
    }

    @Test(arguments: ["not json", "[1,2,3]", ""])
    func malformedFileIsMalformed(body: String) {
        #expect(throws: ProviderError.credentialsMalformed("muse_json")) {
            try Support.source(file: body).load()
        }
    }

    @Test func malformedKeychainPayloadIsMalformed() {
        #expect(throws: ProviderError.credentialsMalformed("muse_json")) {
            try Support.source(keychainJSON: "{{").load()
        }
    }

    @Test func unreadableAndOversizedFiles() {
        #expect(throws: ProviderError.credentialsUnreadable("muse_file")) {
            try Support.source(fileUnreadable: true).load()
        }
        let huge = String(repeating: " ", count: MuseCredentialSource.maxFileBytes + 1)
        #expect(throws: ProviderError.credentialsMalformed("muse_file_size")) {
            try Support.source(file: huge).load()
        }
    }

    @Test(arguments: [
        (KeychainReadError.interactionRequired, "muse_keychain_interaction_required"),
        (KeychainReadError.accessDenied(status: -34018), "muse_keychain_access_denied"),
        (KeychainReadError.unexpectedStatus(-1), "muse_keychain_unexpected_status"),
    ])
    func keychainFailuresAreUnreadable(error: KeychainReadError, reason: String) {
        #expect(throws: ProviderError.credentialsUnreadable(reason)) {
            try Support.source(keychainError: error).load()
        }
    }

    @Test func pathPrecedenceHonoursAbsoluteOverridesOnly() {
        let plain = { (url: URL) -> String in url.standardizedFileURL.path(percentEncoded: false) }
        let byDefault = Support.defaultAuthURL(Support.environment())
        #expect(plain(byDefault) == "/Users/tester/.config/muse/auth.json")

        let xdg = Support.defaultAuthURL(Support.environment(variables: ["XDG_CONFIG_HOME": "/opt/xdg"]))
        #expect(plain(xdg) == "/opt/xdg/muse/auth.json")

        let relativeXDG = Support.defaultAuthURL(Support.environment(variables: ["XDG_CONFIG_HOME": "xdg"]))
        #expect(plain(relativeXDG) == "/Users/tester/.config/muse/auth.json")

        let direct = Support.defaultAuthURL(Support.environment(variables: [
            "MUSE_AUTH_PATH": " /var/muse/../muse/auth.json ", "XDG_CONFIG_HOME": "/opt/xdg",
        ]))
        #expect(plain(direct) == "/var/muse/auth.json")

        let relativeEnvironment = Support.environment(variables: ["MUSE_AUTH_PATH": "muse/auth.json"])
        let relativeDirect = Support.defaultAuthURL(relativeEnvironment)
        #expect(plain(relativeDirect) == "/Users/tester/.config/muse/auth.json")
    }

    @Test func overriddenPathIsWhereTheFileIsRead() throws {
        let environment = Support.environment(variables: ["MUSE_AUTH_PATH": "/var/muse/auth.json"])
        var fileSystem = FakeFileSystem()
        fileSystem.add(URL(filePath: "/var/muse/auth.json"), contents: Support.authFile())
        let source = MuseCredentialSource(
            environment: environment, fileSystem: fileSystem, keychain: FakeKeychainReader()
        )
        #expect(try source.load().accessToken == Support.token)
    }

    @Test func descriptionsNeverRevealSecrets() {
        let credential = MuseCredential(accessToken: "dca:SECRETTOKEN", email: "SECRET@example.com")
        for text in [String(describing: credential), String(reflecting: credential), credential.debugDescription] {
            #expect(!text.contains("SECRET"))
            #expect(text.contains("<redacted>"))
        }
    }
}
