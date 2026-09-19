import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("Redactor")
struct RedactorTests {
    @Test(arguments: [
        "Authorization: Bearer sk-ant-oat01-abcDEF123_-",
        "token sk-ant-oat01-abcdefghijklmnop",
        "key sk-proj-abcdefghijkl1234",
        "xai-abcdefghijklmnop123",
        "jwt eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJhYmMifQ.c2lnbmF0dXJlYWJj",
        "Cookie: sessionKey=sk-ant-sid01-abc",
    ])
    func masksCredentialShapedText(input: String) {
        let output = Redactor.redact(input)
        #expect(output.contains(Redactor.mask))
        #expect(!output.lowercased().contains("abc"))
    }

    @Test func leavesOrdinaryDiagnosticsAlone() {
        let line = "poll ok provider=claude duration_ms=350 status=200"
        #expect(Redactor.redact(line) == line)
    }

    @Test func ignoresShortKeyLikeFragments() {
        #expect(Redactor.redact("task sk-1 done") == "task sk-1 done")
    }
}
