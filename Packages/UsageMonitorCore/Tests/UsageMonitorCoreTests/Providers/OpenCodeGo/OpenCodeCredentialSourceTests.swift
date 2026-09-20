import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("OpenCodeCredentialSource")
struct OpenCodeCredentialSourceTests {
    let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    var authURL: URL { home.appending(path: ".local/share/opencode/auth.json") }

    private func makeSource(contents: String?, variables: [String: String] = [:]) -> OpenCodeCredentialSource {
        var fileSystem = FakeFileSystem()
        if let contents {
            fileSystem.add(authURL, contents: contents)
        }
        return OpenCodeCredentialSource(
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: variables)
        )
    }

    @Test func readsTheGoPlanKey() throws {
        let json = #"{"opencode-go":{"type":"api","key":" sk-go-key "},"#
            + #""anthropic":{"type":"oauth","access":"a","refresh":"r","expires":1790000000000}}"#
        #expect(try makeSource(contents: json).load() == OpenCodeCredential(key: "sk-go-key"))
    }

    @Test func acceptsTheOlderEntryName() throws {
        let json = #"{"opencode":{"type":"api","key":"sk-old"}}"#
        #expect(try makeSource(contents: json).load().key == "sk-old")
        let both = #"{"opencode":{"type":"api","key":"sk-old"},"opencode-go":{"type":"api","key":"sk-new"}}"#
        #expect(try makeSource(contents: both).load().key == "sk-new")
    }

    @Test func fileWithoutGoPlanIsNotLinked() {
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource(contents: #"{"anthropic":{"type":"oauth","access":"a"}}"#).load()
        }
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource(contents: #"{"opencode-go":{"type":"api","key":"   "}}"#).load()
        }
        #expect(throws: ProviderError.credentialsNotFound) {
            try makeSource(contents: #"{"opencode-go":{"type":"api","key":42}}"#).load()
        }
        #expect(throws: ProviderError.credentialsNotFound) { try makeSource(contents: "{}").load() }
    }

    @Test func missingFileIsNotFound() {
        #expect(throws: ProviderError.credentialsNotFound) { try makeSource(contents: nil).load() }
    }

    @Test func fileProblemsAreReported() {
        #expect(throws: ProviderError.credentialsMalformed("opencode_json")) {
            try makeSource(contents: "{nope").load()
        }
        #expect(throws: ProviderError.credentialsMalformed("opencode_json")) {
            try makeSource(contents: "[]").load()
        }

        let environment = UserEnvironment(homeDirectory: home)
        var unreadable = FakeFileSystem()
        unreadable.unreadable.insert(FakeFileSystem.key(authURL))
        #expect(throws: ProviderError.credentialsUnreadable("opencode_file")) {
            try OpenCodeCredentialSource(fileSystem: unreadable, environment: environment).load()
        }

        var huge = FakeFileSystem()
        huge.files[FakeFileSystem.key(authURL)] = Data(repeating: 0x7B, count: 70_000)
        #expect(throws: ProviderError.credentialsMalformed("opencode_file_size")) {
            try OpenCodeCredentialSource(fileSystem: huge, environment: environment).load()
        }
    }

    @Test func dataHomeOverrideIsHonouredOnlyWhenAbsolute() throws {
        var fileSystem = FakeFileSystem()
        fileSystem.add(URL(filePath: "/data/opencode/auth.json"), contents: #"{"opencode-go":{"key":"sk-x"}}"#)
        let absolute = OpenCodeCredentialSource(
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: ["XDG_DATA_HOME": "/data"])
        )
        #expect(try absolute.load().key == "sk-x")
        let relative = OpenCodeCredentialSource(
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: ["XDG_DATA_HOME": "data"])
        )
        #expect(throws: ProviderError.credentialsNotFound) { try relative.load() }
    }

    @Test func descriptionNeverContainsTheKey() {
        let credential = OpenCodeCredential(key: "sk-SECRETSECRET")
        #expect(!String(describing: credential).contains("SECRET"))
        #expect(!String(reflecting: credential).contains("SECRET"))
    }
}
