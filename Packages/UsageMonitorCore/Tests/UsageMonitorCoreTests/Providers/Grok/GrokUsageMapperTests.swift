import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("GrokUsageMapper")
struct GrokUsageMapperTests {
    let fetchedAt = GrokTestEnvironment.now

    private func map(_ fixture: String) throws -> UsageSnapshot {
        try GrokUsageMapper.snapshot(from: Fixtures.data(fixture, subdirectory: "grok"), fetchedAt: fetchedAt)
    }

    @Test func mapsTheFullPayload() throws {
        let snapshot = try map("billing-full")
        #expect(snapshot.provider == .grok)
        #expect(snapshot.planName == "SuperGrok")
        #expect(snapshot.fetchedAt == fetchedAt)
        let window = try #require(snapshot.windows.first)
        #expect(snapshot.windows.count == 1)
        #expect(window.id == "grok.weekly")
        #expect(window.title == "Weekly usage")
        #expect(window.kind == .weekly)
        #expect(window.usedPercent == 58)
        #expect(window.resetsAt == VendorDates.iso8601("2026-09-21T04:41:00Z"))
        #expect(window.windowDuration == 604_800)
    }

    /// Shape captured from a live 200 response on 2026-09-19: no percent, no tier, fractional
    /// seconds with a numeric offset.
    @Test func mapsTheShapeTheProxyActuallyReturns() throws {
        let snapshot = try map("billing-live-shape")
        let window = try #require(snapshot.windows.first)
        #expect(window.usedPercent == 0)
        #expect(window.resetsAt == VendorDates.iso8601("2026-09-22T08:19:44.065928+00:00"))
        #expect(window.windowDuration == 604_800)
        #expect(snapshot.planName == nil)
    }

    @Test func omittedPercentMeansZero() throws {
        let snapshot = try map("billing-zero-omitted")
        #expect(snapshot.windows.first?.usedPercent == 0)
        #expect(snapshot.windows.first?.resetsAt == VendorDates.iso8601("2026-09-21T04:41:00Z"))
        #expect(snapshot.planName == "SuperGrok Heavy")
    }

    @Test func missingPeriodLeavesResetUnknown() throws {
        let snapshot = try map("billing-no-period")
        #expect(snapshot.windows.first?.usedPercent == 12.5)
        #expect(snapshot.windows.first?.resetsAt == nil)
        #expect(snapshot.windows.first?.windowDuration == nil)
        #expect(snapshot.planName == "Premium+")
    }

    @Test func integerPercentAndInvertedPeriod() throws {
        let snapshot = try map("billing-int-percent")
        #expect(snapshot.windows.first?.usedPercent == 4)
        #expect(snapshot.windows.first?.resetsAt == VendorDates.iso8601("2026-09-14T04:41:00Z"))
        #expect(snapshot.windows.first?.windowDuration == nil)
        #expect(snapshot.planName == "Premium")
    }

    @Test func missingConfigIsADecodingError() {
        #expect(throws: ProviderError.decoding("grok_no_config")) { try map("billing-no-config") }
    }

    @Test func malformedJSONIsADecodingError() {
        #expect(throws: ProviderError.decoding("grok_json")) { try map("billing-malformed") }
        #expect(throws: ProviderError.decoding("grok_json")) {
            try GrokUsageMapper.snapshot(from: Data(), fetchedAt: fetchedAt)
        }
    }

    @Test func nonFinitePercentIsRejected() {
        #expect(throws: ProviderError.decoding("grok_percent")) { try map("billing-nan-percent") }
    }

    @Test func outOfRangePercentIsClamped() throws {
        let json = #"{"config":{"creditUsagePercent":250.0},"subscriptionTier":"SuperGrok"}"#
        let snapshot = try GrokUsageMapper.snapshot(from: Data(json.utf8), fetchedAt: fetchedAt)
        #expect(snapshot.windows.first?.usedPercent == 100)
    }

    @Test(arguments: [
        ("SuperGrok", "SuperGrok"),
        ("supergrok", "SuperGrok"),
        ("SuperGrokHeavy", "SuperGrok Heavy"),
        ("SuperGrok Heavy", "SuperGrok Heavy"),
        ("super_grok_heavy", "SuperGrok Heavy"),
        ("PremiumPlus", "Premium+"),
        ("Premium", "Premium"),
        ("Enterprise", "Enterprise"),
    ])
    func planNamesAreHumanised(tier: String, expected: String) {
        #expect(GrokUsageMapper.planName(from: tier) == expected)
    }

    @Test(arguments: ["Free", "free", "", "   "])
    func freeOrEmptyTiersHaveNoPlanName(tier: String) {
        #expect(GrokUsageMapper.planName(from: tier) == nil)
    }

    @Test func nilTierHasNoPlanName() {
        #expect(GrokUsageMapper.planName(from: nil) == nil)
    }
}
