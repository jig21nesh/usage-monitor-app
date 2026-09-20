import Foundation
import Synchronization
@testable import UsageMonitorCore

/// In-memory stand-in for Cursor's state database.
final class FakeSQLiteReader: SQLiteKeyValueReader, Sendable {
    private let state: Mutex<[String: String]>
    private let failure: SQLiteReadError?

    init(values: [String: String] = [:], failure: SQLiteReadError? = nil) {
        state = Mutex(values)
        self.failure = failure
    }

    func value(forKey key: String, table: String, in databaseURL: URL) throws(SQLiteReadError) -> String? {
        if let failure { throw failure }
        return state.withLock { $0[key] }
    }
}

enum CursorTestData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    static func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A Cursor-shaped JWT: `auth0|` subject, expiry relative to the fixed clock.
    static func jwt(
        expiresIn seconds: TimeInterval = 30 * 86_400,
        subject: String = "auth0|user_01SECRETSUBJECT",
        marker: String = "SECRETSECRET"
    ) -> String {
        let exp = Int(now.timeIntervalSince1970 + seconds)
        let payload = #"{"sub":"\#(subject)","exp":\#(exp),"aud":"https://api2.cursor.sh","scope":"openid"}"#
        return "\(base64URL(#"{"alg":"RS256"}"#)).\(base64URL(payload)).\(marker)"
    }

    static func source(
        database: FakeSQLiteReader = FakeSQLiteReader(),
        keychain: FakeKeychainReader = FakeKeychainReader(),
        fileSystem: FakeFileSystem = FakeFileSystem(),
        variables: [String: String] = [:]
    ) -> CursorCredentialSource {
        CursorCredentialSource(
            environment: UserEnvironment(homeDirectory: home, variables: variables),
            database: database,
            keychain: keychain,
            fileSystem: fileSystem,
            now: { now }
        )
    }

    static func credential(token: String = jwt(), membership: String? = "pro") -> CursorCredential {
        CursorCredential(
            accessToken: token,
            subject: "user_01SECRETSUBJECT",
            expiresAt: now.addingTimeInterval(30 * 86_400),
            email: "someone@example.com",
            membershipType: membership
        )
    }
}
