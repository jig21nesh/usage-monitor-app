import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("UsageWindow")
struct UsageWindowTests {
    @Test("clamps usedPercent into 0...100", arguments: [
        (-5.0, 0.0), (0.0, 0.0), (42.5, 42.5), (100.0, 100.0), (250.0, 100.0),
        (Double.nan, 0.0), (Double.infinity, 0.0), (-Double.infinity, 0.0),
    ])
    func clampsUsedPercent(input: Double, expected: Double) {
        let window = UsageWindow(id: "w", title: "W", kind: .session, usedPercent: input)
        #expect(window.usedPercent == expected)
        #expect(window.remainingPercent == 100 - expected)
    }

    @Test func decodingClampsAndAllowsMissingOptionals() throws {
        let json = #"{"id":"w","title":"Weekly","kind":"weekly","usedPercent":140}"#
        let window = try JSONDecoder().decode(UsageWindow.self, from: Data(json.utf8))
        #expect(window.usedPercent == 100)
        #expect(window.resetsAt == nil)
        #expect(window.windowDuration == nil)
        #expect(window.kind == .weekly)
    }

    @Test func codableRoundTrip() throws {
        let original = UsageWindow(
            id: "claude.weekly.fable",
            title: "Fable",
            kind: .weeklyModel,
            usedPercent: 56,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            windowDuration: 604_800
        )
        let decoded = try JSONDecoder().decode(UsageWindow.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func decodingRejectsUnknownKind() {
        let json = #"{"id":"w","title":"W","kind":"lunar","usedPercent":1}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UsageWindow.self, from: Data(json.utf8))
        }
    }
}

@Suite("UsageSnapshot")
struct UsageSnapshotTests {
    @Test func mostUsedWindowPicksHighestPercent() {
        let low = UsageWindow(id: "a", title: "A", kind: .session, usedPercent: 10)
        let high = UsageWindow(id: "b", title: "B", kind: .weekly, usedPercent: 90)
        let snapshot = UsageSnapshot(provider: .claude, planName: "Max", windows: [low, high], fetchedAt: .now)
        #expect(snapshot.mostUsedWindow == high)
    }

    @Test func emptySnapshotHasNoMostUsedWindow() {
        let snapshot = UsageSnapshot(provider: .grok, planName: nil, windows: [], fetchedAt: .now)
        #expect(snapshot.mostUsedWindow == nil)
    }

    @Test func codableRoundTrip() throws {
        let original = UsageSnapshot.sample(provider: .openAI, planName: "Pro", usedPercent: 58)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
