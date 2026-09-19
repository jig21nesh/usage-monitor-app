import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("VendorDates")
struct VendorDatesTests {
    let expected = Date(timeIntervalSince1970: 1_790_000_000)

    @Test(arguments: [
        "2026-09-21T14:13:20Z",
        "2026-09-21T14:13:20+00:00",
        "2026-09-21T14:13:20.000000+00:00",
        "2026-09-21T14:13:20.000Z",
        "2026-09-22T00:13:20+10:00",
        " 2026-09-21T14:13:20Z ",
    ])
    func parsesEveryVendorShape(value: String) {
        #expect(VendorDates.iso8601(value) == expected)
    }

    @Test(arguments: ["", "   ", "tomorrow", "2026-09-21", "1790000000"])
    func rejectsNonDates(value: String) {
        #expect(VendorDates.iso8601(value) == nil)
    }

    @Test func nilInIsNilOut() {
        #expect(VendorDates.iso8601(nil) == nil)
        #expect(VendorDates.epoch(nil) == nil)
    }

    @Test func epochHandlesSecondsAndMilliseconds() {
        #expect(VendorDates.epoch(1_790_000_000) == expected)
        #expect(VendorDates.epoch(1_790_000_000_000) == expected)
        #expect(VendorDates.epoch(0) == nil)
        #expect(VendorDates.epoch(-5) == nil)
        #expect(VendorDates.epoch(.nan) == nil)
    }
}
