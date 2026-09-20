import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("OpenCodeGoUsageMapper")
struct OpenCodeGoUsageMapperTests {
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func map(_ fixture: String) throws -> UsageSnapshot {
        let data = try Fixtures.data(fixture, subdirectory: "opencode")
        return try OpenCodeGoUsageMapper.snapshot(from: data, fetchedAt: fetchedAt)
    }

    private func map(json: String) throws -> UsageSnapshot {
        try OpenCodeGoUsageMapper.snapshot(from: Data(json.utf8), fetchedAt: fetchedAt)
    }

    @Test func mapsAllThreeWindows() throws {
        let snapshot = try map("usage-go")
        #expect(snapshot.provider == .opencodeGo)
        #expect(snapshot.planName == "Go")
        #expect(snapshot.windows.map(\.id) == ["opencode.session", "opencode.weekly", "opencode.monthly"])
        #expect(snapshot.windows.map(\.title) == ["Current session", "Weekly limit", "Monthly limit"])
        #expect(snapshot.windows.map(\.kind) == [.session, .weekly, .monthly])
        #expect(snapshot.windows.map(\.usedPercent) == [12.5, 40, 73])
        #expect(snapshot.windows.map(\.windowDuration) == [18_000, 604_800, nil])
        #expect(snapshot.windows[0].resetsAt == VendorDates.iso8601("2026-09-20T15:00:00Z"))
        #expect(snapshot.windows[2].resetsAt == VendorDates.iso8601("2026-10-01T00:00:00Z"))
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test func epochResetsAndPartialPayloads() throws {
        let snapshot = try map("usage-epoch")
        #expect(snapshot.windows.map(\.id) == ["opencode.weekly"])
        #expect(snapshot.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(snapshot.windows.first?.usedPercent == 55)
    }

    @Test func resetVariants() throws {
        let asString = try map(json: #"{"usage":{"monthly":{"percent":1,"resetsAt":"1790000000"}}}"#)
        #expect(asString.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_790_000_000))
        let garbage = try map(json: #"{"usage":{"monthly":{"percent":1,"resetsAt":"soon"}}}"#)
        #expect(garbage.windows.first?.resetsAt == nil)
        let missing = try map(json: #"{"usage":{"monthly":{"percent":1}}}"#)
        #expect(missing.windows.first?.resetsAt == nil)
        let wrongType = try map(json: #"{"usage":{"monthly":{"percent":1,"resetsAt":true}}}"#)
        #expect(wrongType.windows.first?.resetsAt == nil)
    }

    @Test func failures() {
        #expect(throws: ProviderError.decoding("opencode_no_windows")) { try map("usage-empty") }
        #expect(throws: ProviderError.decoding("opencode_no_windows")) { try map(json: "{}") }
        #expect(throws: ProviderError.decoding("opencode_json")) { try map("usage-malformed") }
        #expect(throws: ProviderError.decoding("opencode_json")) { try map(json: "[]") }
        #expect(throws: ProviderError.decoding("opencode_percent")) {
            try map(json: #"{"usage":{"rolling":{"status":"ok","resetsAt":"2026-09-20T15:00:00Z"}}}"#)
        }
    }

    @Test func outOfRangePercentsAreClamped() throws {
        let snapshot = try map(json: #"{"usage":{"rolling":{"percent":250},"weekly":{"percent":-4}}}"#)
        #expect(snapshot.windows.map(\.usedPercent) == [100, 0])
    }
}
