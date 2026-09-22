import Foundation
import Testing
@testable import UsageMonitorCore

/// Every file-backed source must turn a missing home folder grant into the same "grant access"
/// reason, so the UI can say what to do instead of "could not be read" (ADR 0009).
@Suite("Home folder grant mapping across credential sources")
struct HomeFolderGrantMappingTests {
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let expected = ProviderError.credentialsUnreadable(ProviderError.homeFolderNotGranted)

    private var environment: UserEnvironment { UserEnvironment(homeDirectory: home) }

    /// A file system holding a plausible file at every default path, all gated behind a missing grant.
    private var gated: HomeFolderGatedFileSystem {
        var base = FakeFileSystem()
        for path in [
            ".codex/auth.json", ".grok/auth.json", ".config/gh/hosts.yml", ".config/muse/auth.json",
            ".local/share/opencode/auth.json", ".cursor/auth.json",
        ] {
            base.add(home.appending(path: path), contents: "{}")
        }
        return HomeFolderGatedFileSystem(base: base, access: FakeHomeFolderAccess(expectedDirectory: home))
    }

    @Test func codexFileReportsMissingGrant() {
        let source = CodexAuthFileCredentialSource(environment: environment, fileSystem: gated)
        #expect(throws: expected) { try source.load() }
    }

    @Test func grokFileReportsMissingGrant() {
        let source = GrokBuildCredentialSource(environment: environment, fileSystem: gated, now: { now })
        #expect(throws: expected) { try source.load() }
        #expect(GrokBuildCredentialSource.map(.accessNotGranted) == expected)
    }

    @Test func copilotHostsFileReportsMissingGrantWhenNoKeychainItemExists() {
        let source = CopilotCredentialSource(
            keychain: FakeKeychainReader(), fileSystem: gated, environment: environment
        )
        #expect(throws: expected) { try source.load() }
    }

    @Test func copilotKeychainLoginDoesNotNeedTheGrant() throws {
        let keychain = FakeKeychainReader(
            items: [CopilotCredentialSource.ghKeychainService: Data("gho_test_token".utf8)]
        )
        let source = CopilotCredentialSource(keychain: keychain, fileSystem: gated, environment: environment)
        #expect(try source.load().token == "gho_test_token")
    }

    @Test func cursorCliFileReportsMissingGrantAfterDatabaseAndKeychainMiss() {
        let source = CursorCredentialSource(
            environment: environment,
            database: FakeSQLiteReader(failure: .notFound),
            keychain: FakeKeychainReader(),
            fileSystem: gated,
            now: { now }
        )
        #expect(throws: expected) { try source.load() }
    }

    @Test func museFileReportsMissingGrant() {
        let source = MuseCredentialSource(environment: environment, fileSystem: gated, keychain: FakeKeychainReader())
        #expect(throws: expected) { try source.load() }
    }

    @Test func museKeychainLoginDoesNotNeedTheGrant() throws {
        let keychain = FakeKeychainReader(
            items: [MuseCredentialSource.keychainService: Data(#"{"access_token":"dca:test_token_0123456789"}"#.utf8)]
        )
        let source = MuseCredentialSource(environment: environment, fileSystem: gated, keychain: keychain)
        #expect(try source.load().accessToken == "dca:test_token_0123456789")
    }

    @Test func openCodeFileReportsMissingGrant() {
        let source = OpenCodeCredentialSource(fileSystem: gated, environment: environment)
        #expect(throws: expected) { try source.load() }
    }

    @Test func absoluteOverridesOutsideTheHomeFolderStillRead() throws {
        var base = FakeFileSystem()
        base.add(URL(filePath: "/opt/codex/auth.json"), contents: "{}")
        let fileSystem = HomeFolderGatedFileSystem(base: base, access: FakeHomeFolderAccess(expectedDirectory: home))
        let source = CodexAuthFileCredentialSource(
            environment: UserEnvironment(homeDirectory: home, variables: ["CODEX_HOME": "/opt/codex"]),
            fileSystem: fileSystem
        )
        // The file is reachable; it merely lacks the fields, which is a different error.
        do throws(ProviderError) {
            _ = try source.load()
            Issue.record("an empty auth file must not load")
        } catch {
            #expect(error != expected)
        }
    }
}
