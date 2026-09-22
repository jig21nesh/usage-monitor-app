import Foundation

/// The subset of the Muse Code CLI login the app needs. Only `dca:` OAuth tokens can read
/// subscription usage; `LLM|` API keys are rejected before any request is made (ADR 0008).
/// Printing an instance never reveals the token or the email.
public struct MuseCredential: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let tokenPrefix = "dca:"

    public let accessToken: String
    /// Display-only label for the Accounts view; never logged.
    public let email: String?

    public init(accessToken: String, email: String?) {
        self.accessToken = accessToken
        self.email = email
    }

    public var description: String {
        "MuseCredential(email: \(email == nil ? "none" : "<redacted>"), accessToken: <redacted>)"
    }

    public var debugDescription: String { description }
}

/// Reads the login written by `muse login` (ADR 0002): the auth file first, then the keychain item
/// the CLI uses when it is configured for keychain storage. Never writes and never refreshes.
public struct MuseCredentialSource: CredentialSource {
    public typealias Credential = MuseCredential

    public static let maxFileBytes = 65_536
    public static let keychainService = "ai.meta.dev.credentials"
    public static let keychainAccount = "meta"
    static let authPathVariable = "MUSE_AUTH_PATH"
    static let xdgConfigVariable = "XDG_CONFIG_HOME"

    let fileURL: URL
    let fileSystem: any FileSystem
    let keychain: any KeychainReader

    public init(environment: UserEnvironment, fileSystem: any FileSystem, keychain: any KeychainReader) {
        fileURL = Self.resolveFileURL(environment)
        self.fileSystem = fileSystem
        self.keychain = keychain
    }

    /// `MUSE_AUTH_PATH` (absolute) beats `$XDG_CONFIG_HOME/muse/auth.json` (absolute) beats
    /// `~/.config/muse/auth.json`, mirroring the CLI. Relative values are ignored on purpose.
    static func resolveFileURL(_ environment: UserEnvironment) -> URL {
        if let raw = environment.variables[authPathVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.hasPrefix("/") {
            return URL(filePath: raw).standardizedFileURL
        }
        return environment
            .directory(overrideVariable: xdgConfigVariable, defaultRelativePath: ".config")
            .appending(path: "muse")
            .appending(path: "auth.json")
    }

    public func load() throws(ProviderError) -> MuseCredential {
        // A missing home folder grant (ADR 0009) must not hide a keychain login; it only decides
        // the final error when the keychain has nothing either.
        let fileLogin: FileLogin?
        var grantMissing = false
        do throws(ProviderError) {
            fileLogin = try readFile()
        } catch .credentialsUnreadable(let reason) where reason == ProviderError.homeFolderNotGranted {
            fileLogin = nil
            grantMissing = true
        }
        if let token = fileLogin?.token {
            return try Self.validated(token, email: fileLogin?.email)
        }
        // The file is absent, holds no token, or says `"storage": "keychain"`: the CLI then keeps
        // the token in the keychain item.
        if let credential = try readKeychain(emailHint: fileLogin?.email) {
            return credential
        }
        if grantMissing {
            throw .credentialsUnreadable(ProviderError.homeFolderNotGranted)
        }
        throw .credentialsNotFound
    }

    struct FileLogin {
        let token: String?
        let email: String?
    }

    private func readFile() throws(ProviderError) -> FileLogin? {
        let data: Data
        do {
            data = try fileSystem.read(at: fileURL, maxBytes: Self.maxFileBytes)
        } catch {
            switch error {
            case .notFound: return nil
            case .notReadable: throw .credentialsUnreadable("muse_file")
            case .accessNotGranted: throw .credentialsUnreadable(ProviderError.homeFolderNotGranted)
            case .tooLarge: throw .credentialsMalformed("muse_file_size")
            }
        }
        guard let root = Self.jsonObject(data) else { throw .credentialsMalformed("muse_json") }
        let meta = Self.metaProvider(in: root)
        return FileLogin(
            token: Self.nonEmptyString(meta?["access_token"] ?? root["access_token"]),
            email: Self.nonEmptyString(meta?["email"] ?? root["email"])
        )
    }

    private func readKeychain(emailHint: String?) throws(ProviderError) -> MuseCredential? {
        let data: Data?
        do {
            data = try keychain.genericPassword(service: Self.keychainService, account: Self.keychainAccount)
        } catch {
            throw .credentialsUnreadable(Self.reason(for: error))
        }
        guard let data else { return nil }
        guard let root = Self.jsonObject(data) else { throw .credentialsMalformed("muse_json") }
        let meta = Self.metaProvider(in: root)
        guard let token = Self.nonEmptyString(root["access_token"] ?? meta?["access_token"]) else {
            return nil
        }
        let email = Self.nonEmptyString(root["email"] ?? meta?["email"]) ?? emailHint
        return try Self.validated(token, email: email)
    }

    /// Only OAuth tokens can read subscription usage; an inference API key would just get a 401,
    /// so it is rejected up front with a message that points at `muse login`.
    static func validated(_ token: String, email: String?) throws(ProviderError) -> MuseCredential {
        guard token.hasPrefix(MuseCredential.tokenPrefix) else {
            throw .credentialsMalformed("muse_token_kind")
        }
        return MuseCredential(accessToken: token, email: email)
    }

    static func jsonObject(_ data: Data) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    static func metaProvider(in root: [String: Any]) -> [String: Any]? {
        guard let providers = root["providers"] as? [String: Any] else { return nil }
        return providers["meta"] as? [String: Any]
    }

    static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    static func reason(for error: KeychainReadError) -> String {
        switch error {
        case .interactionRequired: "muse_keychain_interaction_required"
        case .accessDenied: "muse_keychain_access_denied"
        case .unexpectedStatus: "muse_keychain_unexpected_status"
        }
    }
}
