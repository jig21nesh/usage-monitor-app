import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("OpenAIUsageMapper")
struct OpenAIUsageMapperTests {
    typealias Support = OpenAITestSupport
    typealias Mapper = OpenAIUsageMapper

    private func map(_ fixture: String, credential: OpenAICredential = Support.credential) throws -> UsageSnapshot {
        try Mapper.snapshot(from: try Support.fixture(fixture), credential: credential, now: Support.now)
    }

    @Test func proAccountHasSessionThenWeekly() throws {
        let snapshot = try map("usage-pro")
        #expect(snapshot.provider == .openAI)
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.fetchedAt == Support.now)
        #expect(snapshot.windows.map(\.id) == ["openai.session", "openai.weekly"])
        #expect(snapshot.windows.map(\.title) == ["Current session", "Weekly usage limit"])
        #expect(snapshot.windows.map(\.kind) == [.session, .weekly])
        #expect(snapshot.windows.map(\.usedPercent) == [12, 58])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_789_958_460))
        #expect(snapshot.windows[1].resetsAt == Date(timeIntervalSince1970: 1_790_081_000))
        #expect(snapshot.windows.map(\.windowDuration) == [18_000, 604_800])
    }

    @Test func plusAccountWithOnlyWeeklyWindowIsClassifiedByLength() throws {
        let snapshot = try map("usage-plus-weekly-only")
        #expect(snapshot.planName == "Plus")
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].id == "openai.weekly")
        #expect(snapshot.windows[0].kind == .weekly)
        #expect(snapshot.windows[0].usedPercent == 58)
        #expect(snapshot.windows[0].remainingPercent == 42)
    }

    @Test func swappedWindowsAreReorderedSessionFirst() throws {
        let snapshot = try map("usage-swapped-windows")
        #expect(snapshot.planName == "Team")
        #expect(snapshot.windows.map(\.id) == ["openai.session", "openai.weekly"])
        #expect(snapshot.windows.map(\.usedPercent) == [5, 70])
    }

    @Test func additionalLimitsBecomePerModelWindows() throws {
        let snapshot = try map("usage-additional-limits")
        #expect(snapshot.windows.map(\.id) == [
            "openai.session",
            "openai.weekly",
            "openai.gpt-5-5-codex.session",
            "openai.gpt-5-5-codex.weekly",
            "openai.deep-research.window",
        ])
        #expect(snapshot.windows[2].title == "GPT-5.5 Codex (5h)")
        #expect(snapshot.windows[2].kind == .session)
        #expect(snapshot.windows[3].title == "GPT-5.5 Codex")
        #expect(snapshot.windows[3].kind == .weeklyModel)
        #expect(snapshot.windows[3].usedPercent == 81)
        #expect(snapshot.windows[4].title == "Deep Research (30d)")
        #expect(snapshot.windows[4].kind == .other)
        #expect(snapshot.windows[4].resetsAt == Date(timeIntervalSince1970: 1_792_000_000))
    }

    @Test func fractionalPercentAndRelativeResetAreSupported() throws {
        let snapshot = try map("usage-double-percent")
        #expect(snapshot.windows.map(\.usedPercent) == [33.5, 99.9])
        #expect(snapshot.windows[0].resetsAt == Support.now.addingTimeInterval(4200))
        #expect(snapshot.windows[1].resetsAt == Support.now.addingTimeInterval(86_400))
        #expect(snapshot.planName == "Pro", "falls back to the credential plan type")
    }

    @Test func missingPlanEverywhereYieldsNilPlanName() throws {
        let credential = OpenAICredential(accessToken: "t", accountID: nil, planType: nil, email: nil)
        #expect(try map("usage-double-percent", credential: credential).planName == nil)
    }

    @Test func emptyPayloadHasNoWindows() {
        #expect(throws: ProviderError.decoding("openai_no_windows")) { try map("usage-empty") }
    }

    @Test func malformedPayloadIsDecodingError() {
        #expect(throws: ProviderError.decoding("openai_json")) { try map("usage-malformed") }
    }

    @Test func windowWithoutPercentIsRejected() {
        let json = #"{"rate_limit":{"primary_window":{"limit_window_seconds":18000,"reset_at":1}}}"#
        #expect(throws: ProviderError.decoding("openai_percent")) {
            try Mapper.snapshot(from: Data(json.utf8), credential: Support.credential, now: Support.now)
        }
    }

    @Test func percentWithWrongTypeIsDecodingError() {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":"lots","limit_window_seconds":18000}}}"#
        #expect(throws: ProviderError.decoding("openai_json")) {
            try Mapper.snapshot(from: Data(json.utf8), credential: Support.credential, now: Support.now)
        }
    }

    @Test func windowWithoutLengthIsKeptAsUnknown() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":7}}}"#
        let snapshot = try Mapper.snapshot(from: Data(json.utf8), credential: Support.credential, now: Support.now)
        #expect(snapshot.windows.map(\.id) == ["openai.window.unknown"])
        #expect(snapshot.windows[0].title == "Usage window")
        #expect(snapshot.windows[0].kind == .other)
        #expect(snapshot.windows[0].resetsAt == nil)
        #expect(snapshot.windows[0].windowDuration == nil)
    }

    @Test func negativeResetAfterIsIgnored() throws {
        let json = #"{"rate_limit":{"primary_window":"#
            + #"{"used_percent":7,"limit_window_seconds":18000,"reset_after_seconds":-5}}}"#
        let snapshot = try Mapper.snapshot(from: Data(json.utf8), credential: Support.credential, now: Support.now)
        #expect(snapshot.windows[0].resetsAt == nil)
    }

    @Test(arguments: [
        (18_000.0, Mapper.WindowClass.session),
        (16_200.0, .session),
        (19_800.0, .session),
        (20_000.0, .other(seconds: 20_000)),
        (604_800.0, .weekly),
        (544_320.0, .weekly),
        (665_280.0, .weekly),
        (700_000.0, .other(seconds: 700_000)),
        (2_592_000.0, .other(seconds: 2_592_000)),
    ])
    func classifiesByWindowLength(seconds: Double, expected: Mapper.WindowClass) {
        #expect(Mapper.classify(seconds) == expected)
    }

    @Test(arguments: [nil, 0.0, -1.0, Double.nan, Double.infinity])
    func unusableLengthsAreUnknown(seconds: Double?) {
        #expect(Mapper.classify(seconds) == .unknown)
    }

    @Test func otherWindowTitlesDescribeTheSpan() {
        #expect(Mapper.WindowClass.other(seconds: 43_200).accountTitle == "12 hour window")
        #expect(Mapper.WindowClass.other(seconds: 172_800).accountTitle == "2 day window")
        #expect(Mapper.WindowClass.other(seconds: 2_592_000).accountTitle == "30 day window")
        #expect(Mapper.WindowClass.other(seconds: 43_200).additionalTitle("Search") == "Search (12h)")
        #expect(Mapper.WindowClass.other(seconds: 2_592_000).accountID == "openai.window.2592000")
        #expect(Mapper.WindowClass.unknown.additionalTitle("Search") == "Search")
    }

    @Test(arguments: [
        ("GPT-5.5 Codex!!", "gpt-5-5-codex"),
        ("deep_research", "deep-research"),
        ("  spaced   out  ", "spaced-out"),
        ("", "limit"),
        ("---", "limit"),
    ])
    func slugifies(input: String, expected: String) {
        #expect(Mapper.slugify(input) == expected)
    }

    @Test(arguments: [
        ("plus", "Plus"), ("pro", "Pro"), ("prolite", "Pro Lite"), ("team", "Team"), ("business", "Business"),
        ("free", "Free"), ("go", "Go"), ("guest", "Guest"), ("enterprise", "Enterprise"), ("ent26", "Enterprise"),
        (" PRO ", "Pro"), ("self_serve_business_plus", "Self_serve_business_plus"),
    ])
    func planDisplayNames(raw: String, expected: String) {
        #expect(OpenAIPlan.displayName(raw) == expected)
    }

    @Test(arguments: [nil, "", "   "])
    func emptyPlanIsNil(raw: String?) {
        #expect(OpenAIPlan.displayName(raw) == nil)
    }
}
