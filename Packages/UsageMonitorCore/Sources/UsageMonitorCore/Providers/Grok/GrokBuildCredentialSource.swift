import Foundation

/// Reads `auth.json` written by the Grok Build CLI (`grok login`). The CLI refreshes its own
/// token; this source never writes and never refreshes (ADR 0002).
public struct GrokBuildCredentialSource: CredentialSource {
    public typealias Credential = GrokCredential

    public static let maxFileBytes = 65_536
    static let homeOverrideVariable = "GROK_HOME"
    static let defaultDirectory = ".grok"
    static let preferredIssuerPrefix = "https://auth.x.ai"

    let fileURL: URL
    let fileSystem: any FileSystem
    let now: @Sendable () -> Date

    public init(environment: UserEnvironment, fileSystem: any FileSystem, now: @escaping @Sendable () -> Date) {
        fileURL = environment
            .directory(overrideVariable: Self.homeOverrideVariable, defaultRelativePath: Self.defaultDirectory)
            .appending(path: "auth.json")
        self.fileSystem = fileSystem
        self.now = now
    }

    public func load() throws(ProviderError) -> GrokCredential {
        let data: Data
        do {
            data = try fileSystem.read(at: fileURL, maxBytes: Self.maxFileBytes)
        } catch {
            throw Self.map(error)
        }
        let entry = try Self.selectEntry(from: data)
        guard let token = entry["key"] as? String, !token.isEmpty else {
            throw .credentialsMalformed("grok_json")
        }
        let expiresAt = Self.expiry(entry["expires_at"])
        if let expiresAt, expiresAt <= now() {
            throw .credentialsExpired
        }
        return GrokCredential(
            accessToken: token,
            userID: entry["user_id"] as? String,
            email: entry["email"] as? String,
            expiresAt: expiresAt
        )
    }

    static func map(_ error: FileReadError) -> ProviderError {
        switch error {
        case .notFound: .credentialsNotFound
        case .notReadable: .credentialsUnreadable("grok_file")
        case .tooLarge: .credentialsMalformed("grok_file_size")
        }
    }

    /// Grok Build 1.x nests the login under an `"<issuer>::<client_id>"` key; earlier builds wrote
    /// the fields at the top level. Both are accepted, and the xAI issuer wins when several
    /// logins exist so behaviour does not depend on dictionary order.
    static func selectEntry(from data: Data) throws(ProviderError) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw .credentialsMalformed("grok_json")
        }
        if root["key"] is String {
            return root
        }
        let candidates = root.compactMap { key, value -> (issuer: String, entry: [String: Any])? in
            guard let entry = value as? [String: Any], entry["key"] is String else { return nil }
            return (key, entry)
        }
        let ordered = candidates.sorted { lhs, rhs in
            let lhsPreferred = lhs.issuer.hasPrefix(preferredIssuerPrefix)
            let rhsPreferred = rhs.issuer.hasPrefix(preferredIssuerPrefix)
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.issuer < rhs.issuer
        }
        guard let chosen = ordered.first else {
            throw .credentialsMalformed("grok_json")
        }
        return chosen.entry
    }

    /// `expires_at` has been seen as RFC 3339 text; numbers are accepted as epoch seconds or
    /// milliseconds in case the CLI changes its mind.
    static func expiry(_ raw: Any?) -> Date? {
        switch raw {
        case let number as NSNumber:
            return VendorDates.epoch(number.doubleValue)
        case let text as String:
            return VendorDates.iso8601(text) ?? VendorDates.epoch(Double(text))
        default:
            return nil
        }
    }
}
