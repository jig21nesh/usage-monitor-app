import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("GrokBuildCredentialSource")
struct GrokBuildCredentialSourceTests {
    typealias Env = GrokTestEnvironment

    @Test func loadsTheNestedLayoutWrittenByGrokBuildOnePointX() throws {
        let credential = try Env.source(authJSON: GrokAuthJSON.nested()).load()
        #expect(credential.accessToken == "grok-token")
        #expect(credential.userID == "user-1")
        #expect(credential.email == "me@example.com")
        #expect(credential.expiresAt == VendorDates.iso8601("2099-01-01T00:00:00Z"))
    }

    @Test func loadsTheFlatLayout() throws {
        let credential = try Env.source(authJSON: GrokAuthJSON.flat(email: nil, userID: nil)).load()
        #expect(credential.accessToken == "grok-token")
        #expect(credential.userID == nil)
        #expect(credential.email == nil)
    }

    @Test func prefersTheXAIIssuerWhenSeveralLoginsExist() throws {
        let json = GrokAuthJSON.nested([
            "https://auth.example.com::aaaa": GrokAuthJSON.entry(key: "other-token"),
            GrokAuthJSON.issuerKey: GrokAuthJSON.entry(key: "xai-token"),
            "zzz": "not an entry",
            "https://auth.example.com::bbbb": ["no_key_here": true],
        ])
        #expect(try Env.source(authJSON: json).load().accessToken == "xai-token")
    }

    @Test func fallsBackToAlphabeticalIssuerOrderWithoutXAI() throws {
        let json = GrokAuthJSON.nested([
            "https://b.example::1": GrokAuthJSON.entry(key: "b-token"),
            "https://a.example::1": GrokAuthJSON.entry(key: "a-token"),
        ])
        #expect(try Env.source(authJSON: json).load().accessToken == "a-token")
    }

    @Test func expiryAcceptsEpochSecondsMillisecondsIsoOrNothing() throws {
        let expected = Date(timeIntervalSince1970: 4_102_444_800)
        func expiry(_ raw: Any?) throws -> Date? {
            try Env.source(authJSON: GrokAuthJSON.nested(expiresAt: raw)).load().expiresAt
        }
        #expect(try expiry(4_102_444_800) == expected)
        #expect(try expiry(4_102_444_800_000) == expected)
        #expect(try expiry("2100-01-01T00:00:00Z") == expected)
        #expect(try expiry("4102444800") == expected)
        #expect(try expiry(nil) == nil)
        #expect(try expiry(["odd"]) == nil)
    }

    @Test func expiredTokenIsReportedWithoutBeingReturned() {
        let source = Env.source(authJSON: GrokAuthJSON.nested(expiresAt: "2020-01-01T00:00:00Z"))
        #expect(throws: ProviderError.credentialsExpired) { try source.load() }
        let boundary = Env.source(authJSON: GrokAuthJSON.nested(expiresAt: Env.now.timeIntervalSince1970), now: Env.now)
        #expect(throws: ProviderError.credentialsExpired) { try boundary.load() }
    }

    @Test func missingFileMeansNotLinked() {
        #expect(throws: ProviderError.credentialsNotFound) { try Env.source(authJSON: nil).load() }
    }

    @Test func unreadableAndOversizedFilesAreDistinguished() {
        var unreadable = FakeFileSystem()
        unreadable.unreadable.insert(FakeFileSystem.key(Env.authFile))
        let unreadableSource = GrokBuildCredentialSource(
            environment: Env.environment(), fileSystem: unreadable, now: { Env.now }
        )
        #expect(throws: ProviderError.credentialsUnreadable("grok_file")) { try unreadableSource.load() }

        let huge = String(repeating: " ", count: GrokBuildCredentialSource.maxFileBytes + 1)
        let hugeSource = Env.source(authJSON: huge)
        #expect(throws: ProviderError.credentialsMalformed("grok_file_size")) { try hugeSource.load() }
    }

    @Test(arguments: [
        "not json at all",
        "[1, 2, 3]",
        "{}",
        #"{"key": ""}"#,
        #"{"key": 42}"#,
        #"{"https://auth.x.ai::x": {"email": "me@example.com"}}"#,
        #"{"https://auth.x.ai::x": {"key": ""}}"#,
        #"{"https://auth.x.ai::x": "just a string"}"#,
    ])
    func malformedDocumentsAreRejected(json: String) {
        #expect(throws: ProviderError.credentialsMalformed("grok_json")) { try Env.source(authJSON: json).load() }
    }

    @Test func honoursAbsoluteGrokHomeAndIgnoresRelativeOne() throws {
        var fileSystem = FakeFileSystem()
        fileSystem.add(URL(filePath: "/opt/grok/auth.json"), contents: GrokAuthJSON.nested(key: "opt-token"))
        let absolute = GrokBuildCredentialSource(
            environment: Env.environment(variables: ["GROK_HOME": "/opt/grok"]),
            fileSystem: fileSystem,
            now: { Env.now }
        )
        #expect(try absolute.load().accessToken == "opt-token")

        let relative = GrokBuildCredentialSource(
            environment: Env.environment(variables: ["GROK_HOME": "opt/grok"]),
            fileSystem: fileSystem,
            now: { Env.now }
        )
        #expect(throws: ProviderError.credentialsNotFound) { try relative.load() }
    }

    @Test func descriptionsNeverRevealTheToken() {
        let credential = GrokCredential(accessToken: "SECRETSECRETTOKEN", userID: "u", email: "e@x", expiresAt: nil)
        #expect(!String(describing: credential).contains("SECRET"))
        #expect(!String(reflecting: credential).contains("SECRET"))
        #expect(!"\(credential)".contains("SECRET"))
    }
}
