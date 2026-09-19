import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("PercentStyle setting")
struct PercentStyleTests {
    @Test func settingsSavedBeforeTheKeyExistedStillDecode() throws {
        let legacy = #"{"enabledProviders":["claude"],"refreshInterval":300,"#
            + #""launchAtLogin":true,"hasCompletedOnboarding":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(settings.percentStyle == .used)
        #expect(settings.enabledProviders == [.claude])
        #expect(settings.refreshInterval == .fiveMinutes)
        #expect(settings.launchAtLogin)
        #expect(settings.hasCompletedOnboarding)
    }

    @Test func roundTripsThroughCodable() throws {
        var settings = AppSettings.default
        settings.percentStyle = .remaining
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.percentStyle == .remaining)
    }

    @Test func defaultsAndTitles() {
        #expect(AppSettings.default.percentStyle == .used)
        #expect(PercentStyle.allCases == [.used, .remaining])
        #expect(PercentStyle.used.title == "Percent used")
        #expect(PercentStyle.remaining.title == "Percent left")
        #expect(PercentStyle.remaining.id == "remaining")
    }

    @Test func rejectsUnknownStyleValues() {
        let json = #"{"enabledProviders":[],"refreshInterval":60,"launchAtLogin":false,"#
            + #""hasCompletedOnboarding":false,"percentStyle":"fraction"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        }
    }
}
