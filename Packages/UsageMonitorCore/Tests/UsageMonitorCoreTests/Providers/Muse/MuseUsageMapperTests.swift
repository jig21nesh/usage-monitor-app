import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("MuseUsageMapper")
struct MuseUsageMapperTests {
    typealias Support = MuseTestSupport

    private func map(_ json: String) throws(ProviderError) -> UsageSnapshot {
        try MuseUsageMapper.snapshot(from: Data(json.utf8), fetchedAt: Support.fetchedAt)
    }

    @Test func activeSubscriptionMapsBothWindows() throws {
        let snapshot = try MuseUsageMapper.snapshot(from: Support.fixture("key-active"), fetchedAt: Support.fetchedAt)
        #expect(snapshot.provider == .muse)
        #expect(snapshot.planName == "Power Usage")
        #expect(snapshot.fetchedAt == Support.fetchedAt)
        #expect(snapshot.windows.map(\.id) == ["muse.session", "muse.weekly"])

        let session = try #require(snapshot.windows.first)
        #expect(session.title == "Current session")
        #expect(session.kind == .session)
        #expect(session.usedPercent == 37)
        #expect(session.windowDuration == 18_000)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_790_005_000))

        let weekly = try #require(snapshot.windows.last)
        #expect(weekly.title == "Weekly limit")
        #expect(weekly.kind == .weekly)
        #expect(weekly.usedPercent == 12.5)
        #expect(weekly.windowDuration == 604_800)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_790_400_000))
    }

    @Test func inactiveSubscriptionIsPayAsYouGoWithoutMeters() throws {
        let snapshot = try MuseUsageMapper.snapshot(from: Support.fixture("key-inactive"), fetchedAt: Support.fetchedAt)
        #expect(snapshot.planName == MuseUsageMapper.payAsYouGoPlan)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func activeWithoutUsageKeepsTheTierAndNoMeters() throws {
        let snapshot = try MuseUsageMapper.snapshot(
            from: Support.fixture("key-active-no-usage"),
            fetchedAt: Support.fetchedAt
        )
        #expect(snapshot.planName == "Everyday Usage")
        #expect(snapshot.windows.isEmpty)
    }

    @Test func apiKeyIsNeverDecodedOrSurfaced() throws {
        let data = try Support.fixture("key-with-api-key")
        let snapshot = try MuseUsageMapper.snapshot(from: data, fetchedAt: Support.fetchedAt)
        #expect(!String(describing: snapshot).contains("SECRETKEY"))
        #expect(!String(reflecting: snapshot).contains("SECRETKEY"))
        #expect(snapshot.planName == "High Usage")
        // Same fixture also exercises clamping, custom duration, millisecond epochs and garbage resets.
        let session = try #require(snapshot.windows.first)
        #expect(session.usedPercent == 100)
        #expect(session.windowDuration == 36_000)
        #expect(session.resetsAt == Date(timeIntervalSince1970: 1_790_005_000))
        let weekly = try #require(snapshot.windows.last)
        #expect(weekly.resetsAt == nil)
    }

    @Test func emptyObjectIsAnActiveAccountWithNothingKnown() throws {
        let snapshot = try map("{}")
        #expect(snapshot.planName == nil)
        #expect(snapshot.windows.isEmpty)
    }

    @Test func malformedBodyIsADecodingError() throws {
        let data = try Support.fixture("key-malformed")
        #expect(throws: ProviderError.decoding("muse_json")) {
            try MuseUsageMapper.snapshot(from: data, fetchedAt: Support.fetchedAt)
        }
        #expect(throws: ProviderError.decoding("muse_json")) { try map("[]") }
    }

    @Test(arguments: ["NaN", "Infinity", "-Infinity"])
    func nonFinitePercentIsRejected(value: String) {
        let json = #"{"is_subs_active":true,"subs_usage":{"window":{"used_percent":"\#(value)"}}}"#
        #expect(throws: ProviderError.decoding("muse_percent")) { try map(json) }
        let weekly = #"{"is_subs_active":true,"subs_usage":{"weekly":{"used_percent":"\#(value)"}}}"#
        #expect(throws: ProviderError.decoding("muse_percent")) { try map(weekly) }
    }

    @Test func windowsWithoutAPercentAreSkipped() throws {
        let json = #"{"is_subs_active":true,"subs_tier_name":"High Usage","#
            + #""subs_usage":{"window":{"resets_at":1790005000},"weekly":{"used_percent":40}}}"#
        let snapshot = try map(json)
        #expect(snapshot.windows.map(\.id) == ["muse.weekly"])
    }

    @Test(arguments: [(nil, 18_000.0), (0.0, 18_000.0), (-5.0, 18_000.0), (300.0, 18_000.0), (60.0, 3_600.0)])
    func sessionDurationFallsBackToFiveHours(minutes: Double?, expected: TimeInterval) {
        #expect(MuseUsageMapper.sessionDuration(minutes: minutes) == expected)
    }

    @Test func resetDatesOutsideAPlausibleRangeAreDropped() {
        #expect(MuseUsageMapper.resetDate(nil) == nil)
        #expect(MuseUsageMapper.resetDate(1) == nil)
        #expect(MuseUsageMapper.resetDate(5_000_000_000) == nil)
        #expect(MuseUsageMapper.resetDate(1_790_000_000) == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(MuseUsageMapper.resetDate(1_790_000_000_000) == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func planNameIsTrimmedAndNilWhenEmpty() {
        #expect(MuseUsageMapper.planName(from: "  High Usage ") == "High Usage")
        #expect(MuseUsageMapper.planName(from: "   ") == nil)
        #expect(MuseUsageMapper.planName(from: nil) == nil)
    }
}
