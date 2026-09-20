import Foundation

/// The OpenCode Go plan key the OpenCode CLI stored at `opencode auth login`. Printing an
/// instance never reveals the key.
public struct OpenCodeCredential: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let key: String

    public init(key: String) {
        self.key = key
    }

    public var description: String { "OpenCodeCredential(key: <redacted>)" }
    public var debugDescription: String { description }
}

/// Reads `$XDG_DATA_HOME/opencode/auth.json` (default `~/.local/share/opencode/auth.json`). The
/// file maps provider ids to entries such as `{"type":"api","key":"sk-…"}`; only the Go plan
/// entry is of interest, because pay-as-you-go Zen keys expose no usage windows (ADR 0008).
public struct OpenCodeCredentialSource: CredentialSource {
    public static let maxFileBytes = 65_536
    /// Provider ids under which the Go plan key has been stored, newest naming first.
    static let goEntryKeys = ["opencode-go", "opencode"]

    private let fileSystem: any FileSystem
    private let environment: UserEnvironment

    public init(fileSystem: any FileSystem, environment: UserEnvironment) {
        self.fileSystem = fileSystem
        self.environment = environment
    }

    public var fileURL: URL {
        environment
            .directory(overrideVariable: "XDG_DATA_HOME", defaultRelativePath: ".local/share")
            .appending(path: "opencode/auth.json")
    }

    public func load() throws(ProviderError) -> OpenCodeCredential {
        let data: Data
        do {
            data = try fileSystem.read(at: fileURL, maxBytes: Self.maxFileBytes)
        } catch {
            switch error {
            case .notFound: throw .credentialsNotFound
            case .notReadable: throw .credentialsUnreadable("opencode_file")
            case .tooLarge: throw .credentialsMalformed("opencode_file_size")
            }
        }
        let entries: [String: Entry]
        do {
            entries = try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            throw .credentialsMalformed("opencode_json")
        }
        // A user with OpenCode but no Go plan has a file without the Go entry: not logged in, for us.
        for name in Self.goEntryKeys {
            if let key = entries[name]?.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return OpenCodeCredential(key: key)
            }
        }
        throw .credentialsNotFound
    }

    /// Other providers' entries carry OAuth fields of mixed types; only a string `key` is read,
    /// and anything else in an entry is ignored rather than failing the whole file.
    struct Entry: Decodable {
        let key: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try? container.decodeIfPresent(String.self, forKey: .key)
        }

        enum CodingKeys: String, CodingKey {
            case key
        }
    }
}
