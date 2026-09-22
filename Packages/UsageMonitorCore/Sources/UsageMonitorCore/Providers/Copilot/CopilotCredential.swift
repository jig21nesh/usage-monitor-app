import Foundation

/// A GitHub token the user already created by signing in to the GitHub CLI or the Copilot CLI.
/// `login` is display-only. Printing an instance never reveals the token.
public struct CopilotCredential: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let token: String
    /// Which local store supplied the token, shown as the account origin ("GitHub CLI").
    public let source: String
    public let login: String?

    public init(token: String, source: String, login: String?) {
        self.token = token
        self.source = source
        self.login = login
    }

    public var description: String {
        "CopilotCredential(source: \(source), login: \(login ?? "unknown"), token: <redacted>)"
    }

    public var debugDescription: String { description }
}

/// Reads the login the GitHub CLI (or Copilot CLI) already holds, in the order those tools use
/// themselves (ADR 0002, ADR 0008): keychain item `gh:github.com`, then `hosts.yml`, then the
/// Copilot CLI keychain item, then `GH_TOKEN` / `GITHUB_TOKEN`. `~/.copilot/config.json` holds no
/// token (only trusted folders and UI flags), so it is deliberately not consulted.
public struct CopilotCredentialSource: CredentialSource {
    public static let ghKeychainService = "gh:github.com"
    public static let copilotKeychainService = "copilot-cli"
    public static let tokenEnvironmentVariables = ["GH_TOKEN", "GITHUB_TOKEN"]
    static let maxFileBytes = 65_536
    static let ghOrigin = "GitHub CLI"
    static let copilotOrigin = "Copilot CLI"
    static let environmentOrigin = "Environment"

    private let keychain: any KeychainReader
    private let fileSystem: any FileSystem
    private let environment: UserEnvironment

    public init(keychain: any KeychainReader, fileSystem: any FileSystem, environment: UserEnvironment) {
        self.keychain = keychain
        self.fileSystem = fileSystem
        self.environment = environment
    }

    public var hostsURL: URL {
        environment
            .directory(overrideVariable: "GH_CONFIG_DIR", defaultRelativePath: ".config/gh")
            .appending(path: "hosts.yml")
    }

    public func load() throws(ProviderError) -> CopilotCredential {
        // Read hosts.yml first so the login name is available even when the token lives in the keychain.
        // A missing home folder grant (ADR 0009) must not hide a keychain login, so it only decides
        // the final error when nothing else is found.
        let hosts: Hosts?
        var grantMissing = false
        do throws(ProviderError) {
            hosts = try readHosts()
        } catch .credentialsUnreadable(let reason) where reason == ProviderError.homeFolderNotGranted {
            hosts = nil
            grantMissing = true
        }
        var firstKeychainFailure: ProviderError?

        switch keychainToken(service: Self.ghKeychainService) {
        case .success(let token?):
            return CopilotCredential(token: token, source: Self.ghOrigin, login: hosts?.login)
        case .success(nil):
            break
        case .failure(let error):
            firstKeychainFailure = error
        }

        if let token = hosts?.token {
            return CopilotCredential(token: token, source: Self.ghOrigin, login: hosts?.login)
        }

        switch keychainToken(service: Self.copilotKeychainService) {
        case .success(let token?):
            return CopilotCredential(token: token, source: Self.copilotOrigin, login: hosts?.login)
        case .success(nil):
            break
        case .failure(let error):
            firstKeychainFailure = firstKeychainFailure ?? error
        }

        for variable in Self.tokenEnvironmentVariables {
            if let raw = environment.variables[variable]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return CopilotCredential(token: raw, source: Self.environmentOrigin, login: hosts?.login)
            }
        }

        if let firstKeychainFailure {
            throw firstKeychainFailure
        }
        if grantMissing {
            throw .credentialsUnreadable(ProviderError.homeFolderNotGranted)
        }
        throw .credentialsNotFound
    }

    // MARK: - Keychain

    private func keychainToken(service: String) -> Result<String?, ProviderError> {
        let data: Data?
        do {
            data = try keychain.genericPassword(service: service, account: nil)
        } catch {
            return .failure(.credentialsUnreadable(Self.reason(for: error)))
        }
        guard let data else { return .success(nil) }
        return .success(Self.token(fromKeychainData: data))
    }

    /// `gh` writes its keychain item through go-keyring, which on macOS base64-encodes the value
    /// behind this prefix so it survives round-tripping through the `security` tool.
    static let goKeyringPrefix = "go-keyring-base64:"

    /// `gh` stores the token go-keyring-wrapped (older setups bare); other tools may wrap it in
    /// JSON. All three are accepted.
    static func token(fromKeychainData data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix(Self.goKeyringPrefix) {
            return goKeyringToken(String(trimmed.dropFirst(Self.goKeyringPrefix.count)))
        }
        if trimmed.hasPrefix("{"),
           let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] {
            for key in ["oauth_token", "access_token", "token"] {
                if let value = object[key] as? String, !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        return trimmed
    }

    /// Nil for malformed base64, non-UTF-8 bytes or an empty payload, so the caller falls through
    /// to the next store instead of sending garbage to GitHub.
    private static func goKeyringToken(_ payload: String) -> String? {
        guard let bytes = Data(base64Encoded: payload),
              let decoded = String(data: bytes, encoding: .utf8) else { return nil }
        let token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func reason(for error: KeychainReadError) -> String {
        switch error {
        case .interactionRequired: "gh_keychain_interaction_required"
        case .accessDenied: "gh_keychain_access_denied"
        case .unexpectedStatus: "gh_keychain_unexpected_status"
        }
    }

    // MARK: - hosts.yml

    struct Hosts: Equatable {
        var token: String?
        var login: String?
    }

    private func readHosts() throws(ProviderError) -> Hosts? {
        let data: Data
        do {
            data = try fileSystem.read(at: hostsURL, maxBytes: Self.maxFileBytes)
        } catch {
            switch error {
            case .notFound: return nil
            case .notReadable: throw .credentialsUnreadable("gh_hosts")
            case .accessNotGranted: throw .credentialsUnreadable(ProviderError.homeFolderNotGranted)
            case .tooLarge: throw .credentialsMalformed("gh_hosts_size")
            }
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw .credentialsMalformed("gh_hosts")
        }
        return Self.parseHosts(text)
    }

    /// A deliberately small YAML reader for the two layouts `gh` has written: `oauth_token` and
    /// `user` directly under `github.com:`, or nested under `users: <login>:`. Indentation width
    /// and quoting vary between versions, so only relative indentation is trusted.
    static func parseHosts(_ text: String) -> Hosts? {
        let lines = text.components(separatedBy: .newlines)
        guard let hostIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "github.com:" })
        else { return nil }
        let hostIndent = indentation(of: lines[hostIndex])
        var hosts = Hosts()
        var usersIndent: Int?
        var firstUserKey: String?

        for line in lines[(hostIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = indentation(of: line)
            if indent <= hostIndent { break }

            if trimmed == "users:" {
                usersIndent = indent
                continue
            }
            if let value = value(of: "oauth_token", in: trimmed) {
                hosts.token = hosts.token ?? value
            } else if let value = value(of: "user", in: trimmed) {
                hosts.login = value
            } else if let usersIndent, indent > usersIndent, firstUserKey == nil,
                      trimmed.hasSuffix(":"), !trimmed.dropLast().contains(":") {
                firstUserKey = String(trimmed.dropLast())
            }
        }
        hosts.login = hosts.login ?? firstUserKey
        return hosts
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func value(of key: String, in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix(key + ":") else { return nil }
        var value = trimmedLine.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last,
           first == last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
