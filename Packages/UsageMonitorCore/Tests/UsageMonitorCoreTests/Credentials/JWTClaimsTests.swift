import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("JWTClaims")
struct JWTClaimsTests {
    struct Claims: Decodable, Equatable {
        let sub: String
        let plan: String?
    }

    private func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func jwt(payload: String) -> String {
        "\(base64URL(#"{"alg":"none"}"#)).\(base64URL(payload)).signature"
    }

    @Test func decodesPayloadClaims() throws {
        let claims = try JWTClaims.payload(of: jwt(payload: #"{"sub":"user-1","plan":"pro"}"#), as: Claims.self)
        #expect(claims == Claims(sub: "user-1", plan: "pro"))
    }

    @Test(arguments: ["onlyone", "two.parts", "a.b.c.d", ""])
    func rejectsWrongSegmentCount(token: String) {
        #expect(throws: ProviderError.credentialsMalformed("jwt_segments")) {
            try JWTClaims.payload(of: token, as: Claims.self)
        }
    }

    @Test func rejectsUndecodablePayload() {
        #expect(throws: ProviderError.credentialsMalformed("jwt_payload_encoding")) {
            try JWTClaims.payload(of: "h.!!!not-base64!!!.s", as: Claims.self)
        }
    }

    @Test func rejectsPayloadWithWrongShape() {
        #expect(throws: ProviderError.credentialsMalformed("jwt_payload_shape")) {
            try JWTClaims.payload(of: jwt(payload: #"{"sub":1}"#), as: Claims.self)
        }
    }

    @Test(arguments: [("YQ", "a"), ("YWI", "ab"), ("YWJj", "abc"), ("YWJjZA", "abcd")])
    func base64URLDecodingRestoresPadding(encoded: String, expected: String) {
        let data = JWTClaims.base64URLDecode(encoded)
        #expect(data.flatMap { String(data: $0, encoding: .utf8) } == expected)
    }
}
