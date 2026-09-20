import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CursorUsageMapper")
struct CursorUsageMapperTests {
    let now = CursorTestData.now
    let credential = CursorTestData.credential()

    private func snapshot(_ fixture: String) throws -> UsageSnapshot {
        let data = try Fixtures.data(fixture, subdirectory: "cursor")
        return try CursorUsageMapper.snapshot(from: data, credential: credential, now: now)
    }

    @Test func mapsIncludedAndOnDemandWindowsFromTheProShape() throws {
        let result = try snapshot("period-usage-pro")
        #expect(result.provider == .cursor)
        #expect(result.planName == "Pro")
        #expect(result.fetchedAt == now)
        #expect(result.windows.map(\.id) == ["cursor.included", "cursor.on-demand"])

        let included = result.windows[0]
        #expect(included.title == "Included usage")
        #expect(included.kind == .monthly)
        #expect(included.usedPercent == 58)
        #expect(included.resetsAt == Date(timeIntervalSince1970: 1_760_572_800))
        #expect(included.windowDuration == 2_592_000.0)

        let onDemand = result.windows[1]
        #expect(onDemand.kind == .other)
        #expect(onDemand.usedPercent == 5)
        #expect(onDemand.resetsAt == included.resetsAt)
    }

    @Test func mapsTheShapeObservedLiveInSeptember2026() throws {
        let result = try snapshot("period-usage-live-shape")
        #expect(result.windows.map(\.id) == ["cursor.included"])
        #expect(result.windows[0].usedPercent == 32)
        #expect(result.windows[0].resetsAt == Date(timeIntervalSince1970: 1_791_049_895))
        #expect(result.windows[0].windowDuration == 2_592_000.0)
    }

    @Test func limitMinusRemainingIsTheLastResortPercent() throws {
        let json = #"{"planUsage":{"remaining":1500,"limit":2000,"remainingBonus":false}}"#
        let result = try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        #expect(result.windows[0].usedPercent == 25)
    }

    @Test func pooledLimitIsUsedWhenNoIndividualLimitAndPlanHasNoLimit() throws {
        let result = try snapshot("period-usage-spend-only")
        #expect(result.windows.map(\.id) == ["cursor.on-demand"])
        #expect(result.windows[0].usedPercent == 75)
        #expect(result.windows[0].resetsAt == Date(timeIntervalSince1970: 1_760_572_800))
    }

    @Test func noUsableLimitsIsADecodingError() {
        #expect(throws: ProviderError.decoding("cursor_no_windows")) {
            try snapshot("period-usage-no-limits")
        }
    }

    @Test func spendOverLimitIsUsedWhenServerPercentIsAbsent() throws {
        let json = #"{"billingCycleEnd":"1760572800000","planUsage":{"totalSpend":500,"limit":2000}}"#
        let result = try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        #expect(result.windows.count == 1)
        #expect(result.windows[0].usedPercent == 25)
        #expect(result.windows[0].windowDuration == nil)
    }

    @Test func includedSpendIsTheFallbackWhenTotalSpendIsMissing() throws {
        let json = #"{"planUsage":{"includedSpend":1000,"limit":4000}}"#
        let result = try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        #expect(result.windows[0].usedPercent == 25)
        #expect(result.windows[0].resetsAt == nil)
    }

    @Test func percentsAboveOneHundredAreClampedByTheWindow() throws {
        let json = #"{"planUsage":{"totalPercentUsed":140}}"#
        let result = try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        #expect(result.windows[0].usedPercent == 100)
    }

    @Test func isoCycleDatesAreAccepted() throws {
        let json = #"{"billingCycleStart":"2026-09-16T00:00:00Z","billingCycleEnd":"2026-10-16T00:00:00Z","#
            + #""planUsage":{"totalPercentUsed":10}}"#
        let result = try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        #expect(result.windows[0].resetsAt == VendorDates.iso8601("2026-10-16T00:00:00Z"))
        #expect(result.windows[0].windowDuration == 2_592_000.0)
    }

    @Test func nonFinitePercentIsRejected() {
        let json = #"{"planUsage":{"totalPercentUsed":"NaN"}}"#
        #expect(throws: ProviderError.decoding("cursor_json")) {
            try CursorUsageMapper.snapshot(from: Data(json.utf8), credential: credential, now: now)
        }
        #expect(throws: ProviderError.decoding("cursor_percent")) {
            try CursorUsageMapper.includedPercent(.init(
                totalSpend: nil, includedSpend: nil, bonusSpend: nil, limit: nil, remaining: nil,
                totalPercentUsed: .infinity
            ))
        }
        #expect(throws: ProviderError.decoding("cursor_percent")) {
            try CursorUsageMapper.onDemandPercent(.init(
                individualLimit: 100, individualUsed: .nan, pooledLimit: nil, pooledUsed: nil, limitType: nil
            ))
        }
    }

    @Test(arguments: ["not json", "", "[]", #"{"planUsage": 5}"#])
    func malformedPayloadsAreDecodingErrors(body: String) {
        #expect(throws: ProviderError.decoding("cursor_json")) {
            try CursorUsageMapper.snapshot(from: Data(body.utf8), credential: credential, now: now)
        }
    }

    @Test func emptyObjectHasNoWindows() {
        #expect(throws: ProviderError.decoding("cursor_no_windows")) {
            try CursorUsageMapper.snapshot(from: Data("{}".utf8), credential: credential, now: now)
        }
    }

    @Test func cycleDatesAcceptNumbersStringsAndISO() {
        let expected = Date(timeIntervalSince1970: 1_760_572_800)
        #expect(CursorUsageMapper.cycleDate(.number(1_760_572_800_000)) == expected)
        #expect(CursorUsageMapper.cycleDate(.text(" 1760572800 ")) == expected)
        #expect(CursorUsageMapper.cycleDate(.text("garbage")) == nil)
        #expect(CursorUsageMapper.cycleDate(nil) == nil)
    }

    @Test func planNameComesFromTheCredentialNotThePayload() throws {
        let unknownPlan = CursorTestData.credential(membership: nil)
        let result = try CursorUsageMapper.snapshot(
            from: Fixtures.data("period-usage-pro", subdirectory: "cursor"), credential: unknownPlan, now: now
        )
        #expect(result.planName == nil)
    }
}
