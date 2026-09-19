import Foundation

/// Decodes the payload of a JWT for display-only claims (plan type, account id). Signatures are
/// deliberately not verified: the app makes no security decision on these claims (ADR 0002).
public enum JWTClaims {
    public static func payload<T: Decodable>(
        of token: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws(ProviderError) -> T {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { throw .credentialsMalformed("jwt_segments") }
        guard let data = base64URLDecode(String(segments[1])) else {
            throw .credentialsMalformed("jwt_payload_encoding")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .credentialsMalformed("jwt_payload_shape")
        }
    }

    static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }
}
