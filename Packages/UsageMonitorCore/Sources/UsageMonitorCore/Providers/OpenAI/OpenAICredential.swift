import Foundation

/// What the Codex CLI login gives us. `email` and `planType` are display-only claims.
public struct OpenAICredential: Sendable, Hashable {
    public let accessToken: String
    public let accountID: String?
    public let planType: String?
    public let email: String?

    public init(accessToken: String, accountID: String?, planType: String?, email: String?) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.planType = planType
        self.email = email
    }
}

/// Reads `$CODEX_HOME/auth.json` (default `~/.codex/auth.json`) written by `codex login`.
/// The refresh token in that file is deliberately never decoded: refresh tokens rotate, and
/// refreshing from a second process logs the CLI out (ADR 0002).
public struct CodexAuthFileCredentialSource: CredentialSource {
    public static let maxFileBytes = 65_536

    private let environment: UserEnvironment
    private let fileSystem: any FileSystem

    public init(environment: UserEnvironment, fileSystem: any FileSystem) {
        self.environment = environment
        self.fileSystem = fileSystem
    }

    public var fileURL: URL {
        environment
            .directory(overrideVariable: "CODEX_HOME", defaultRelativePath: ".codex")
            .appending(path: "auth.json")
    }

    public func load() throws(ProviderError) -> OpenAICredential {
        let data = try readFile()
        let file: AuthFile
        do {
            file = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw .credentialsMalformed("codex_json")
        }
        // An API-key-only login has no ChatGPT tokens, and an API key cannot read subscription
        // usage, so for this app it is the same as not being logged in.
        guard let tokens = file.tokens,
              let accessToken = tokens.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            throw .credentialsNotFound
        }
        // Claims are optional decoration; a malformed id_token must not block a valid access token.
        let claims = tokens.idToken.flatMap { try? JWTClaims.payload(of: $0, as: IDTokenClaims.self) }
        let fileAccountID = tokens.accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAICredential(
            accessToken: accessToken,
            accountID: (fileAccountID?.isEmpty == false ? fileAccountID : nil) ?? claims?.auth?.accountID,
            planType: claims?.auth?.planType,
            email: claims?.profile?.email
        )
    }

    private func readFile() throws(ProviderError) -> Data {
        do {
            return try fileSystem.read(at: fileURL, maxBytes: Self.maxFileBytes)
        } catch {
            switch error {
            case .notFound: throw .credentialsNotFound
            case .notReadable: throw .credentialsUnreadable("codex_file")
            case .tooLarge: throw .credentialsMalformed("codex_file_size")
            }
        }
    }
}

private struct AuthFile: Decodable {
    let tokens: Tokens?

    struct Tokens: Decodable {
        let idToken: String?
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}

struct IDTokenClaims: Decodable {
    let auth: AuthClaim?
    let profile: ProfileClaim?

    enum CodingKeys: String, CodingKey {
        case auth = "https://api.openai.com/auth"
        case profile = "https://api.openai.com/profile"
    }

    struct AuthClaim: Decodable {
        let accountID: String?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case accountID = "chatgpt_account_id"
            case planType = "chatgpt_plan_type"
        }
    }

    struct ProfileClaim: Decodable {
        let email: String?
    }
}
