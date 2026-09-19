import Foundation
import LocalAuthentication
import Security

public enum KeychainReadError: Error, Sendable, Hashable {
    /// The item exists but reading it needs user consent and interaction was suppressed.
    case interactionRequired
    case accessDenied(status: OSStatus)
    case unexpectedStatus(OSStatus)
}

/// Read-only access to generic-password items. The app never writes to any keychain (ADR 0002).
public protocol KeychainReader: Sendable {
    /// Returns the item's password data, or nil when no such item exists.
    func genericPassword(service: String, account: String?) throws(KeychainReadError) -> Data?
}

public struct SecurityFrameworkKeychainReader: KeychainReader {
    /// When false, macOS returns `errSecInteractionNotAllowed` instead of showing a consent dialog.
    public let allowsUserInteraction: Bool

    public init(allowsUserInteraction: Bool = true) {
        self.allowsUserInteraction = allowsUserInteraction
    }

    public func genericPassword(service: String, account: String?) throws(KeychainReadError) -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let account {
            query[kSecAttrAccount] = account
        }
        if !allowsUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw .interactionRequired
        case errSecAuthFailed, errSecUserCanceled, errSecMissingEntitlement:
            throw .accessDenied(status: status)
        default:
            throw .unexpectedStatus(status)
        }
    }
}
