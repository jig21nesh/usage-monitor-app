import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("OpenAI available resets")
struct OpenAIResetCountTests {
    @Test(arguments: [
        (#"{"available_count":2}"#, 2 as Int?),
        (#"{"available_count":0}"#, 0),
        (#"{"available_count":-1}"#, nil),
        (#"{"available_count":1.5}"#, nil),
        (#"{"available_count":"2"}"#, nil),
        (#"{"available_count":999999999999999999999999999}"#, nil),
        (#"{"available_count":null}"#, nil),
        (#"{}"#, nil),
        (#"[]"#, nil),
        (#"null"#, nil),
    ])
    func optionalMetadataDoesNotBreakUsage(metadata: String, expected: Int?) throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":42,"limit_window_seconds":18000}},"#
            + #""rate_limit_reset_credits":\#(metadata)}"#
        let snapshot = try OpenAIUsageMapper.snapshot(
            from: Data(json.utf8), credential: OpenAITestSupport.credential, now: OpenAITestSupport.now
        )
        #expect(snapshot.availableResetCount == expected)
        #expect(snapshot.windows.first?.usedPercent == 42)
    }

    @Test func olderPayloadDoesNotImplyZeroResets() throws {
        let snapshot = try OpenAIUsageMapper.snapshot(
            from: OpenAITestSupport.fixture("usage-pro"),
            credential: OpenAITestSupport.credential,
            now: OpenAITestSupport.now
        )
        #expect(snapshot.availableResetCount == nil)
    }

    @Test func countSurvivesProviderFetchWithoutAnotherRequest() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, json: #"""
        {"rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000}},
         "rate_limit_reset_credits":{"available_count":3}}
        """#)
        let provider = OpenAIUsageProvider(
            credentials: OpenAIStubCredentialSource(result: .success(OpenAITestSupport.credential)),
            client: OpenAIUsageClient(http: http), now: { OpenAITestSupport.now }
        )
        #expect(try await provider.fetchUsage().availableResetCount == 3)
        #expect(http.requests.count == 1)
        #expect(http.requests.first?.method == .get)
    }

    @Test func snapshotCountRoundTripsAndOlderSnapshotsStillDecode() throws {
        let snapshot = UsageSnapshot(
            provider: .openAI, planName: nil, windows: [], fetchedAt: OpenAITestSupport.now, availableResetCount: 2
        )
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: encoded) == snapshot)
        let legacy = #"{"provider":"openai","windows":[],"fetchedAt":0}"#
        let old = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacy.utf8))
        #expect(old.availableResetCount == nil)
        let invalid = #"{"provider":"openai","windows":[],"fetchedAt":0,"availableResetCount":-1}"#
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: Data(invalid.utf8)).availableResetCount == nil)
    }
}
