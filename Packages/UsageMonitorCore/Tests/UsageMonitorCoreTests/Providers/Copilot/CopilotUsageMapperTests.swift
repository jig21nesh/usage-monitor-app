import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CopilotUsageMapper")
struct CopilotUsageMapperTests {
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func map(_ fixture: String) throws -> UsageSnapshot {
        try CopilotUsageMapper.snapshot(
            from: try Fixtures.data(fixture, subdirectory: "copilot"),
            login: "octocat",
            fetchedAt: fetchedAt
        )
    }

    @Test func individualAccountShowsOnlyThePremiumWindow() throws {
        let snapshot = try map("user-individual")
        #expect(snapshot.provider == .copilot)
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.windows.map(\.id) == ["copilot.premium"])
        let premium = try #require(snapshot.windows.first)
        #expect(premium.title == "Premium requests")
        #expect(premium.kind == .monthly)
        #expect(abs(premium.usedPercent - 16.7) < 0.001)
        #expect(premium.resetsAt == VendorDates.iso8601("2026-10-01T00:00:00Z"))
        #expect(premium.windowDuration == nil)
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test func meteredChatAndCompletionsBecomeExtraWindows() throws {
        let snapshot = try map("user-metered-all")
        #expect(snapshot.planName == "Business")
        #expect(snapshot.windows.map(\.id) == ["copilot.premium", "copilot.chat", "copilot.completions"])
        #expect(snapshot.windows.map(\.title) == ["Premium requests", "Chat", "Completions"])
        #expect(snapshot.windows.map(\.usedPercent) == [10, 40, 75])
        // No top-level reset date: the earliest non-zero per-snapshot epoch is used.
        #expect(snapshot.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_789_900_000))
    }

    @Test func legacyPayloadWithoutPercentIsComputedFromCounts() throws {
        let snapshot = try map("user-legacy-no-percent")
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.usedPercent == 75)
        #expect(snapshot.windows.first?.resetsAt == VendorDates.iso8601("2026-10-01T00:00:00Z"))
        #expect(snapshot.planName == "Business")
    }

    @Test func allUnlimitedMeansNoWindows() {
        #expect(throws: ProviderError.decoding("copilot_no_windows")) { try map("user-unlimited") }
    }

    @Test func malformedAndEmptyPayloads() {
        #expect(throws: ProviderError.decoding("copilot_json")) { try map("user-malformed") }
        #expect(throws: ProviderError.decoding("copilot_no_windows")) {
            try CopilotUsageMapper.snapshot(from: Data("{}".utf8), login: nil, fetchedAt: fetchedAt)
        }
        #expect(throws: ProviderError.decoding("copilot_json")) {
            try CopilotUsageMapper.snapshot(from: Data("[]".utf8), login: nil, fetchedAt: fetchedAt)
        }
    }

    @Test(arguments: [
        ("free", nil, "Free"), ("individual", nil, "Pro"), ("individual_pro", nil, "Pro+"), ("pro_plus", nil, "Pro+"),
        ("business", nil, "Business"), ("enterprise", nil, "Enterprise"), ("trial", nil, "Trial"),
        (nil, "free_educational_quota", "Free"), (nil, "copilot_business_seat", "Business"),
        (nil, "copilot_enterprise_seat", "Enterprise"), (nil, "mystery", nil), (nil, nil, nil), ("", "", nil),
    ])
    func planNames(plan: String?, sku: String?, expected: String?) {
        #expect(CopilotUsageMapper.planName(plan: plan, sku: sku) == expected)
    }

    @Test func bareDateMeansMidnightUTC() {
        #expect(CopilotUsageMapper.midnightUTC("2026-10-01") == VendorDates.iso8601("2026-10-01T00:00:00Z"))
        #expect(CopilotUsageMapper.midnightUTC("2026-10") == nil)
        #expect(CopilotUsageMapper.midnightUTC(nil) == nil)
        #expect(CopilotUsageMapper.midnightUTC("not-a-date!") == nil)
    }

    private func snapshot(
        entitlement: Double? = nil,
        remaining: Double? = nil,
        percentRemaining: Double? = nil,
        unlimited: Bool = false
    ) -> CopilotUsageMapper.Snapshot {
        CopilotUsageMapper.Snapshot(
            entitlement: entitlement,
            remaining: remaining,
            percentRemaining: percentRemaining,
            unlimited: unlimited,
            quotaResetAt: nil
        )
    }

    private func window(_ snapshot: CopilotUsageMapper.Snapshot) throws -> UsageWindow? {
        try CopilotUsageMapper.window(snapshot, id: "x", title: "X", resetsAt: nil)
    }

    @Test func windowEdgeCases() throws {
        #expect(try window(snapshot(entitlement: 10, remaining: 1, percentRemaining: 10, unlimited: true)) == nil)
        #expect(try window(snapshot()) == nil)
        #expect(try window(snapshot(entitlement: 0, remaining: 0)) == nil)
        #expect(try window(snapshot(percentRemaining: 130))?.usedPercent == 0)
        #expect(throws: ProviderError.decoding("copilot_percent")) {
            try window(snapshot(percentRemaining: .nan))
        }
    }
}
