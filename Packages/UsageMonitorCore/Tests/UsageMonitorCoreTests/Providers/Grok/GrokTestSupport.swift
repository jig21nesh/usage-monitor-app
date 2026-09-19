import Foundation
@testable import UsageMonitorCore

/// Builds `auth.json` documents in both layouts the Grok Build CLI has used.
enum GrokAuthJSON {
    static let issuerKey = "https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828"

    static func entry(
        key: Any? = "grok-token",
        expiresAt: Any? = "2099-01-01T00:00:00Z",
        email: String? = "me@example.com",
        userID: String? = "user-1"
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "auth_mode": "oidc",
            "refresh_token": "refresh-should-be-ignored",
            "team_id": "team-1",
            "oidc_issuer": "https://auth.x.ai",
        ]
        if let key { entry["key"] = key }
        if let expiresAt { entry["expires_at"] = expiresAt }
        if let email { entry["email"] = email }
        if let userID { entry["user_id"] = userID }
        return entry
    }

    static func nested(_ entries: [String: Any]) -> String {
        encode(entries)
    }

    static func nested(
        key: Any? = "grok-token",
        expiresAt: Any? = "2099-01-01T00:00:00Z",
        email: String? = "me@example.com",
        userID: String? = "user-1"
    ) -> String {
        encode([issuerKey: entry(key: key, expiresAt: expiresAt, email: email, userID: userID)])
    }

    static func flat(
        key: Any? = "grok-token",
        expiresAt: Any? = "2099-01-01T00:00:00Z",
        email: String? = "me@example.com",
        userID: String? = "user-1"
    ) -> String {
        encode(entry(key: key, expiresAt: expiresAt, email: email, userID: userID))
    }

    static func encode(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

enum GrokTestEnvironment {
    static let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    static let authFile = home.appending(path: ".grok").appending(path: "auth.json")
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func environment(variables: [String: String] = [:]) -> UserEnvironment {
        UserEnvironment(homeDirectory: home, variables: variables)
    }

    static func fileSystem(authJSON: String?) -> FakeFileSystem {
        var fileSystem = FakeFileSystem()
        if let authJSON {
            fileSystem.add(authFile, contents: authJSON)
        }
        return fileSystem
    }

    static func source(
        authJSON: String?,
        variables: [String: String] = [:],
        now: Date = now
    ) -> GrokBuildCredentialSource {
        GrokBuildCredentialSource(
            environment: environment(variables: variables),
            fileSystem: fileSystem(authJSON: authJSON),
            now: { now }
        )
    }

    static func credential(token: String = "grok-token", userID: String? = "user-1") -> GrokCredential {
        GrokCredential(accessToken: token, userID: userID, email: "me@example.com", expiresAt: nil)
    }
}
