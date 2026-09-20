import Foundation

/// Reads the login Cursor already holds on this Mac (ADR 0002, ADR 0008), in order: Cursor.app's
/// state database, the `cursor-agent` CLI keychain item, then the CLI's file store. Nothing is
/// written and the refresh token is never touched; on expiry the user signs in to Cursor again.
public struct CursorCredentialSource: CredentialSource {
    public static let databaseRelativePath = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    public static let tableName = "ItemTable"
    public static let accessTokenKey = "cursorAuth/accessToken"
    public static let emailKey = "cursorAuth/cachedEmail"
    public static let membershipKey = "cursorAuth/stripeMembershipType"
    public static let keychainService = "cursor-access-token"
    public static let keychainAccount = "cursor-user"
    public static let cliAuthRelativePath = ".cursor/auth.json"
    static let maxFileBytes = 65_536
    /// A token about to expire would only earn a 401; treat it as expired now.
    static let expiryGrace: TimeInterval = 60

    private let environment: UserEnvironment
    private let database: any SQLiteKeyValueReader
    private let keychain: any KeychainReader
    private let fileSystem: any FileSystem
    private let now: @Sendable () -> Date

    public init(
        environment: UserEnvironment,
        database: any SQLiteKeyValueReader,
        keychain: any KeychainReader,
        fileSystem: any FileSystem,
        now: @escaping @Sendable () -> Date
    ) {
        self.environment = environment
        self.database = database
        self.keychain = keychain
        self.fileSystem = fileSystem
        self.now = now
    }

    var databaseURL: URL { environment.homeDirectory.appending(path: Self.databaseRelativePath) }
    var cliAuthURL: URL { environment.homeDirectory.appending(path: Self.cliAuthRelativePath) }

    public func load() throws(ProviderError) -> CursorCredential {
        if let credential = try loadFromDatabase() {
            return credential
        }
        if let token = try loadFromKeychain() {
            return try credential(token: token, email: nil, membershipType: nil)
        }
        if let token = try loadFromCLIFile() {
            return try credential(token: token, email: nil, membershipType: nil)
        }
        throw .credentialsNotFound
    }

    private func loadFromDatabase() throws(ProviderError) -> CursorCredential? {
        let token: String?
        do {
            token = try database.value(forKey: Self.accessTokenKey, table: Self.tableName, in: databaseURL)
        } catch .notFound {
            return nil
        } catch .busy {
            throw .credentialsUnreadable("cursor_db_busy")
        } catch {
            throw .credentialsUnreadable("cursor_db")
        }
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        // Email and plan are decoration; a failure reading them must not hide a valid token.
        let email = try? database.value(forKey: Self.emailKey, table: Self.tableName, in: databaseURL)
        let membership = try? database.value(forKey: Self.membershipKey, table: Self.tableName, in: databaseURL)
        return try credential(token: token, email: email, membershipType: membership)
    }

    private func loadFromKeychain() throws(ProviderError) -> String? {
        let data: Data?
        do {
            data = try keychain.genericPassword(service: Self.keychainService, account: Self.keychainAccount)
        } catch {
            throw .credentialsUnreadable("cursor_keychain")
        }
        guard let data,
              let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

    private func loadFromCLIFile() throws(ProviderError) -> String? {
        let data: Data
        do {
            data = try fileSystem.read(at: cliAuthURL, maxBytes: Self.maxFileBytes)
        } catch {
            switch error {
            case .notFound: return nil
            case .notReadable: throw .credentialsUnreadable("cursor_file")
            case .tooLarge: throw .credentialsMalformed("cursor_file_size")
            }
        }
        let file: CLIAuthFile
        do {
            file = try JSONDecoder().decode(CLIAuthFile.self, from: data)
        } catch {
            throw .credentialsMalformed("cursor_json")
        }
        guard let token = file.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            return nil
        }
        return token
    }

    private func credential(
        token: String,
        email: String?,
        membershipType: String?
    ) throws(ProviderError) -> CursorCredential {
        let claims: Claims
        do {
            claims = try JWTClaims.payload(of: token, as: Claims.self)
        } catch {
            throw .credentialsMalformed("cursor_token")
        }
        let expiresAt = VendorDates.epoch(claims.exp)
        if let expiresAt, expiresAt.timeIntervalSince(now()) <= Self.expiryGrace {
            throw .credentialsExpired
        }
        return CursorCredential(
            accessToken: token,
            subject: claims.sub.map(Self.stripAuthPrefix),
            expiresAt: expiresAt,
            email: email?.isEmpty == false ? email : nil,
            membershipType: membershipType?.isEmpty == false ? membershipType : nil
        )
    }

    /// Cursor's subject looks like `auth0|user_01…`; only the part after the bar identifies the user.
    static func stripAuthPrefix(_ subject: String) -> String {
        guard let bar = subject.firstIndex(of: "|") else { return subject }
        return String(subject[subject.index(after: bar)...])
    }

    private struct Claims: Decodable {
        let exp: Double?
        let sub: String?
    }

    private struct CLIAuthFile: Decodable {
        let accessToken: String?
    }
}
