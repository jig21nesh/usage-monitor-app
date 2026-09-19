import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("ClaudeUsageMapper")
struct ClaudeUsageMapperTests {
    let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func map(_ json: String, planName: String? = nil) throws(ProviderError) -> UsageSnapshot {
        try ClaudeUsageMapper.snapshot(from: Data(json.utf8), planName: planName, fetchedAt: fetchedAt)
    }

    @Test func maxFixtureMapsSessionWeeklyAndScopedModel() throws {
        let data = try Fixtures.data("oauth-usage-max", subdirectory: "claude")
        let snapshot = try ClaudeUsageMapper.snapshot(from: data, planName: "Max (20x)", fetchedAt: fetchedAt)

        #expect(snapshot.provider == .claude)
        #expect(snapshot.planName == "Max (20x)")
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.map(\.id) == ["claude.session", "claude.weekly.all", "claude.weekly.fable"])
        #expect(snapshot.windows.map(\.title) == ["Current session", "All models", "Fable"])
        #expect(snapshot.windows.map(\.kind) == [.session, .weekly, .weeklyModel])
        #expect(snapshot.windows.map(\.usedPercent) == [0, 29, 56])
        #expect(snapshot.windows.map(\.windowDuration) == [18_000, 604_800, 604_800])
        #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
        #expect(snapshot.windows[0].resetsAt == VendorDates.iso8601("2026-09-19T05:00:00.000000+00:00"))
        #expect(snapshot.mostUsedWindow?.title == "Fable")
    }

    @Test func legacyFixtureWithoutLimitsFallsBackToBuckets() throws {
        let data = try Fixtures.data("oauth-usage-legacy", subdirectory: "claude")
        let snapshot = try ClaudeUsageMapper.snapshot(from: data, planName: nil, fetchedAt: fetchedAt)

        #expect(snapshot.windows.map(\.id) == ["claude.session", "claude.weekly.all"])
        #expect(snapshot.windows.map(\.usedPercent) == [15, 48])
        #expect(snapshot.windows[0].resetsAt == VendorDates.iso8601("2026-07-19T03:39:59.570750+00:00"))
        #expect(snapshot.planName == nil)
    }

    @Test func emptyLimitsArrayFallsBackAndIncludesPopulatedModelBuckets() throws {
        let data = try Fixtures.data("oauth-usage-opus", subdirectory: "claude")
        let snapshot = try ClaudeUsageMapper.snapshot(from: data, planName: "Pro", fetchedAt: fetchedAt)

        #expect(snapshot.windows.map(\.id) == [
            "claude.session", "claude.weekly.all", "claude.weekly.opus", "claude.weekly.sonnet",
        ])
        #expect(snapshot.windows[2].title == "Opus")
        #expect(snapshot.windows[2].kind == .weeklyModel)
        #expect(snapshot.windows[2].usedPercent == 81.5)
        #expect(snapshot.windows[3].usedPercent == 0)
        #expect(snapshot.windows[3].resetsAt == nil)
    }

    @Test func unknownLimitKindsAreSkippedAndLegacyBucketsUsed() throws {
        let json = #"{"limits":[{"kind":"daily","percent":5}],"five_hour":{"utilization":9,"resets_at":null}}"#
        let snapshot = try map(json)
        #expect(snapshot.windows.map(\.id) == ["claude.session"])
        #expect(snapshot.windows[0].usedPercent == 9)
        #expect(snapshot.windows[0].resetsAt == nil)
    }

    @Test func knownKindsMixedWithUnknownKeepOnlyKnown() throws {
        let json = #"""
        {"limits":[
          {"kind":"session","percent":12,"resets_at":"2026-09-19T05:00:00Z"},
          {"kind":"mystery","percent":99},
          {"kind":"weekly_all","percent":40,"resets_at":"2026-09-21T17:00:00Z"}
        ]}
        """#
        let snapshot = try map(json)
        #expect(snapshot.windows.map(\.id) == ["claude.session", "claude.weekly.all"])
        #expect(snapshot.windows.map(\.usedPercent) == [12, 40])
    }

    @Test func percentAbove100IsClampedByTheWindow() throws {
        let snapshot = try map(#"{"limits":[{"kind":"session","percent":140}]}"#)
        #expect(snapshot.windows[0].usedPercent == 100)
    }

    @Test func negativeLegacyUtilizationIsClamped() throws {
        let snapshot = try map(#"{"seven_day":{"utilization":-3}}"#)
        #expect(snapshot.windows.map(\.id) == ["claude.weekly.all"])
        #expect(snapshot.windows[0].usedPercent == 0)
    }

    @Test func scopedWindowWithoutModelNameUsesGenericTitle() throws {
        let snapshot = try map(#"{"limits":[{"kind":"weekly_scoped","percent":7,"scope":null}]}"#)
        #expect(snapshot.windows[0].id == "claude.weekly.model")
        #expect(snapshot.windows[0].title == "Model")
    }

    @Test func scopedWindowWithBlankNameUsesGenericTitle() throws {
        let json = #"{"limits":[{"kind":"weekly_scoped","percent":7,"#
            + #""scope":{"model":{"display_name":"  "}}}]}"#
        let snapshot = try map(json)
        #expect(snapshot.windows[0].title == "Model")
    }

    @Test func scopedWindowIdIsSluggedFromDisplayName() throws {
        let json = #"{"limits":[{"kind":"weekly_scoped","percent":7,"#
            + #""scope":{"model":{"display_name":"Claude Opus 4.1"}}}]}"#
        let snapshot = try map(json)
        #expect(snapshot.windows[0].id == "claude.weekly.claude-opus-4-1")
        #expect(snapshot.windows[0].title == "Claude Opus 4.1")
    }

    @Test(arguments: [
        ("Fable", "fable"),
        ("Claude Opus 4.1", "claude-opus-4-1"),
        ("  --  ", "model"),
        ("Ünïcode Modèl", "ünïcode-modèl"),
    ])
    func slugging(input: String, expected: String) {
        #expect(ClaudeUsageMapper.slug(input) == expected)
    }

    @Test func missingPercentOnKnownKindIsADecodingError() {
        #expect(throws: ProviderError.decoding("claude_percent")) {
            try map(#"{"limits":[{"kind":"session","resets_at":"2026-09-19T05:00:00Z"}]}"#)
        }
    }

    @Test func missingLegacyUtilizationIsADecodingError() {
        #expect(throws: ProviderError.decoding("claude_percent")) {
            try map(#"{"five_hour":{"resets_at":"2026-09-19T05:00:00Z"}}"#)
        }
    }

    @Test(arguments: ["not json", "", "[]", #"{"limits":[{"kind":"session","percent":"56"}]}"#])
    func malformedPayloadsAreDecodingErrors(json: String) {
        #expect(throws: ProviderError.decoding("claude_json")) {
            try map(json)
        }
    }

    @Test(arguments: ["{}", #"{"limits":[]}"#, #"{"limits":[{"kind":"other","percent":1}],"seven_day":null}"#])
    func payloadsWithoutWindowsAreRejected(json: String) {
        #expect(throws: ProviderError.decoding("claude_no_windows")) {
            try map(json)
        }
    }

    @Test func unparseableResetTimeYieldsNilNotFailure() throws {
        let snapshot = try map(#"{"limits":[{"kind":"session","percent":3,"resets_at":"soon"}]}"#)
        #expect(snapshot.windows[0].resetsAt == nil)
    }
}
