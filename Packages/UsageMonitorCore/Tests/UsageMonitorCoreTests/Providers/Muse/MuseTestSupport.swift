import Foundation
@testable import UsageMonitorCore

enum MuseTestSupport {
    static let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    static let token = "dca:SECRETTOKEN123"
    static let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    static func environment(variables: [String: String] = [:]) -> UserEnvironment {
        UserEnvironment(homeDirectory: home, variables: variables)
    }

    static func defaultAuthURL(_ environment: UserEnvironment) -> URL {
        MuseCredentialSource.resolveFileURL(environment)
    }

    /// Builds a source with an optional auth file body and an optional keychain payload.
    static func source(
        file: String? = nil,
        fileUnreadable: Bool = false,
        keychainJSON: String? = nil,
        keychainError: KeychainReadError? = nil,
        variables: [String: String] = [:]
    ) -> MuseCredentialSource {
        let environment = environment(variables: variables)
        var fileSystem = FakeFileSystem()
        let url = defaultAuthURL(environment)
        if let file {
            fileSystem.add(url, contents: file)
        }
        if fileUnreadable {
            fileSystem.unreadable.insert(FakeFileSystem.key(url))
        }
        var keychain = FakeKeychainReader()
        if let keychainJSON {
            keychain.items[MuseCredentialSource.keychainService] = Data(keychainJSON.utf8)
        }
        keychain.error = keychainError
        return MuseCredentialSource(environment: environment, fileSystem: fileSystem, keychain: keychain)
    }

    static func authFile(
        token: String? = MuseTestSupport.token,
        email: String? = nil,
        storage: String? = nil
    ) -> String {
        var meta: [String] = ["\"mechanism\": \"oauth\""]
        if let token { meta.append("\"access_token\": \"\(token)\"") }
        if let email { meta.append("\"email\": \"\(email)\"") }
        var top: [String] = ["\"providers\": {\"meta\": {\(meta.joined(separator: ", "))}}"]
        if let storage { top.append("\"storage\": \"\(storage)\"") }
        return "{\(top.joined(separator: ", "))}"
    }

    static func credential(email: String? = "dev@example.com") -> MuseCredential {
        MuseCredential(accessToken: token, email: email)
    }

    static func fixture(_ name: String) throws -> Data {
        try Fixtures.data(name, subdirectory: "muse")
    }

    static func provider(
        http: FakeHTTPClient,
        credential: Result<MuseCredential, ProviderError> = .success(credential())
    ) -> MuseUsageProvider {
        MuseUsageProvider(
            credentials: StaticMuseCredentialSource(result: credential),
            client: MuseUsageClient(http: http),
            now: { fetchedAt }
        )
    }
}

struct StaticMuseCredentialSource: CredentialSource {
    let result: Result<MuseCredential, ProviderError>

    func load() throws(ProviderError) -> MuseCredential {
        try result.get()
    }
}
