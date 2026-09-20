import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CopilotCredentialSource")
struct CopilotCredentialSourceTests {
    let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    var hostsURL: URL { home.appending(path: ".config/gh/hosts.yml") }

    static let flatHosts = """
    github.com:
        oauth_token: gho_flat_token
        user: octocat
        git_protocol: https
    """

    static let nestedHosts = """
    # written by gh 2.40+
    github.com:
        git_protocol: https
        users:
            octocat:
                oauth_token: "gho_nested_token"
        user: octocat
    """

    static let keychainHosts = """
    github.com:
        git_protocol: https
        users:
            octocat:
        user: octocat
    """

    private func makeSource(
        keychain: FakeKeychainReader = FakeKeychainReader(),
        hosts: String? = nil,
        variables: [String: String] = [:]
    ) -> CopilotCredentialSource {
        var fileSystem = FakeFileSystem()
        if let hosts {
            fileSystem.add(hostsURL, contents: hosts)
        }
        return CopilotCredentialSource(
            keychain: keychain,
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: variables)
        )
    }

    @Test func keychainTokenWinsAndLoginComesFromHosts() throws {
        let keychain = FakeKeychainReader(items: ["gh:github.com": Data("gho_keychain_token\n".utf8)])
        let credential = try makeSource(keychain: keychain, hosts: Self.keychainHosts).load()
        #expect(credential.token == "gho_keychain_token")
        #expect(credential.source == "GitHub CLI")
        #expect(credential.login == "octocat")
    }

    @Test func flatHostsLayoutSuppliesTokenAndLogin() throws {
        let credential = try makeSource(hosts: Self.flatHosts).load()
        #expect(credential.token == "gho_flat_token")
        #expect(credential.login == "octocat")
        #expect(credential.source == "GitHub CLI")
    }

    @Test func nestedUsersLayoutSuppliesQuotedTokenAndLogin() throws {
        let credential = try makeSource(hosts: Self.nestedHosts).load()
        #expect(credential.token == "gho_nested_token")
        #expect(credential.login == "octocat")
    }

    @Test func nestedLayoutWithoutUserLineFallsBackToFirstUserKey() {
        let hosts = "github.com:\n  users:\n    hubot:\n      oauth_token: gho_h\n"
        #expect(CopilotCredentialSource.parseHosts(hosts) == .init(token: "gho_h", login: "hubot"))
    }

    @Test func copilotCliKeychainItemIsAcceptedInJSONForm() throws {
        let keychain = FakeKeychainReader(items: ["copilot-cli": Data(#"{"token":"ghu_copilot"}"#.utf8)])
        let credential = try makeSource(keychain: keychain).load()
        #expect(credential.token == "ghu_copilot")
        #expect(credential.source == "Copilot CLI")
        #expect(credential.login == nil)
    }

    @Test func environmentVariablesAreTheLastResort() throws {
        let credential = try makeSource(variables: ["GITHUB_TOKEN": " ghp_env "]).load()
        #expect(credential.token == "ghp_env")
        #expect(credential.source == "Environment")
        let preferred = try makeSource(variables: ["GH_TOKEN": "gh_a", "GITHUB_TOKEN": "gh_b"]).load()
        #expect(preferred.token == "gh_a")
    }

    @Test func nothingAnywhereIsNotFound() {
        #expect(throws: ProviderError.credentialsNotFound) { try makeSource().load() }
        #expect(throws: ProviderError.credentialsNotFound) { try makeSource(hosts: Self.keychainHosts).load() }
        #expect(throws: ProviderError.credentialsNotFound) { try makeSource(variables: ["GH_TOKEN": "  "]).load() }
    }

    @Test func keychainFailureOnlySurfacesWhenNothingElseWorks() throws {
        var failing = FakeKeychainReader()
        failing.error = .interactionRequired
        let rescued = try makeSource(keychain: failing, variables: ["GH_TOKEN": "gh_env"]).load()
        #expect(rescued.source == "Environment")
        #expect(throws: ProviderError.credentialsUnreadable("gh_keychain_interaction_required")) {
            try makeSource(keychain: failing).load()
        }
        failing.error = .accessDenied(status: -34018)
        #expect(throws: ProviderError.credentialsUnreadable("gh_keychain_access_denied")) {
            try makeSource(keychain: failing).load()
        }
        failing.error = .unexpectedStatus(-1)
        #expect(throws: ProviderError.credentialsUnreadable("gh_keychain_unexpected_status")) {
            try makeSource(keychain: failing).load()
        }
    }

    private func source(with fileSystem: FakeFileSystem) -> CopilotCredentialSource {
        CopilotCredentialSource(
            keychain: FakeKeychainReader(),
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home)
        )
    }

    @Test func hostsFileProblemsAreReported() {
        var unreadable = FakeFileSystem()
        unreadable.unreadable.insert(FakeFileSystem.key(hostsURL))
        #expect(throws: ProviderError.credentialsUnreadable("gh_hosts")) { try source(with: unreadable).load() }

        var huge = FakeFileSystem()
        huge.files[FakeFileSystem.key(hostsURL)] = Data(repeating: 0x20, count: 70_000)
        #expect(throws: ProviderError.credentialsMalformed("gh_hosts_size")) { try source(with: huge).load() }

        var binary = FakeFileSystem()
        binary.files[FakeFileSystem.key(hostsURL)] = Data([0xFF, 0xFE, 0xFD])
        #expect(throws: ProviderError.credentialsMalformed("gh_hosts")) { try source(with: binary).load() }
    }

    @Test func configDirectoryOverrideIsHonouredOnlyWhenAbsolute() throws {
        var fileSystem = FakeFileSystem()
        fileSystem.add(URL(filePath: "/opt/gh/hosts.yml"), contents: Self.flatHosts)
        let absolute = CopilotCredentialSource(
            keychain: FakeKeychainReader(),
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: ["GH_CONFIG_DIR": "/opt/gh"])
        )
        #expect(try absolute.load().token == "gho_flat_token")

        let relative = CopilotCredentialSource(
            keychain: FakeKeychainReader(),
            fileSystem: fileSystem,
            environment: UserEnvironment(homeDirectory: home, variables: ["GH_CONFIG_DIR": "opt/gh"])
        )
        #expect(throws: ProviderError.credentialsNotFound) { try relative.load() }
    }

    @Test func parserIgnoresOtherHostsCommentsAndTabs() {
        #expect(CopilotCredentialSource.parseHosts("ghe.example.com:\n  oauth_token: x\n") == nil)
        let tabs = "github.com:\n\toauth_token: 'gho_tab'\n\tuser: tabby\nghe.example.com:\n\toauth_token: other\n"
        #expect(CopilotCredentialSource.parseHosts(tabs) == .init(token: "gho_tab", login: "tabby"))
        #expect(CopilotCredentialSource.parseHosts("") == nil)
    }

    @Test func keychainDataParsing() {
        #expect(CopilotCredentialSource.token(fromKeychainData: Data("  gho_x \n".utf8)) == "gho_x")
        #expect(CopilotCredentialSource.token(fromKeychainData: Data(#"{"access_token":"ghu_y"}"#.utf8)) == "ghu_y")
        #expect(CopilotCredentialSource.token(fromKeychainData: Data(#"{"other":"z"}"#.utf8)) == nil)
        #expect(CopilotCredentialSource.token(fromKeychainData: Data()) == nil)
        #expect(CopilotCredentialSource.token(fromKeychainData: Data([0xFF, 0xFE])) == nil)
    }

    @Test func descriptionNeverContainsTheToken() {
        let credential = CopilotCredential(token: "gho_SECRETSECRET", source: "GitHub CLI", login: "octocat")
        #expect(!String(describing: credential).contains("SECRET"))
        #expect(!String(reflecting: credential).contains("SECRET"))
        #expect(String(describing: credential).contains("octocat"))
    }
}
