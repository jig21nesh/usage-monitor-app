import Foundation
@testable import UsageMonitorCore

struct OpenAIStubCredentialSource: CredentialSource {
    let result: Result<OpenAICredential, ProviderError>

    func load() throws(ProviderError) -> OpenAICredential {
        try result.get()
    }
}

enum OpenAITestSupport {
    static let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    static let now = Date(timeIntervalSince1970: 1_789_900_000)

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Builds an unsigned JWT shaped like the Codex id_token (the app never verifies signatures).
    static func jwt(auth: [String: Any]? = nil, profile: [String: Any]? = nil) -> String {
        var payload: [String: Any] = ["sub": "user-1", "aud": "codex"]
        if let auth { payload["https://api.openai.com/auth"] = auth }
        if let profile { payload["https://api.openai.com/profile"] = profile }
        let header = base64URL(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let body = base64URL((try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
        return "\(header).\(body).signature"
    }

    static func authFile(
        accessToken: String? = "access-token-value",
        accountID: String? = "acct_file",
        idToken: String? = nil,
        includeTokens: Bool = true,
        apiKey: String? = nil
    ) -> String {
        var root: [String: Any] = [
            "auth_mode": includeTokens ? "chatgpt" : "apikey",
            "last_refresh": "2026-09-15T23:40:53Z",
        ]
        root["OPENAI_API_KEY"] = apiKey ?? NSNull()
        if includeTokens {
            var tokens: [String: Any] = ["refresh_token": "refresh-token-value"]
            if let accessToken { tokens["access_token"] = accessToken }
            if let accountID { tokens["account_id"] = accountID }
            if let idToken { tokens["id_token"] = idToken }
            root["tokens"] = tokens
        }
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func makeSource(
        contents: String?,
        variables: [String: String] = [:],
        unreadable: Bool = false,
        rawData: Data? = nil
    ) -> CodexAuthFileCredentialSource {
        let environment = UserEnvironment(homeDirectory: home, variables: variables)
        var fileSystem = FakeFileSystem()
        let url = environment.directory(overrideVariable: "CODEX_HOME", defaultRelativePath: ".codex")
            .appending(path: "auth.json")
        if unreadable {
            fileSystem.unreadable.insert(FakeFileSystem.key(url))
        } else if let rawData {
            fileSystem.files[FakeFileSystem.key(url)] = rawData
        } else if let contents {
            fileSystem.add(url, contents: contents)
        }
        return CodexAuthFileCredentialSource(environment: environment, fileSystem: fileSystem)
    }

    static func fixture(_ name: String) throws -> Data {
        try Fixtures.data(name, subdirectory: "openai")
    }

    static let credential = OpenAICredential(
        accessToken: "access-token-value",
        accountID: "acct_1",
        planType: "pro",
        email: "me@example.com"
    )
}
