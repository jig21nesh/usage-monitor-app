import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("Settings")
struct SettingsStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "UsageMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    @Test func defaultsEnableEveryProviderEveryTwoMinutes() {
        let settings = AppSettings.default
        #expect(settings.enabledProviders == Set(ProviderID.allCases))
        #expect(settings.refreshInterval == .twoMinutes)
        #expect(!settings.launchAtLogin)
        #expect(!settings.hasCompletedOnboarding)
    }

    @Test func missingDataYieldsDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == .default)
    }

    @Test func roundTrips() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = AppSettings.default
        settings.enabledProviders = [.claude]
        settings.refreshInterval = .fiveMinutes
        settings.launchAtLogin = true
        settings.hasCompletedOnboarding = true
        store.save(settings)
        #expect(store.load() == settings)
        #expect(defaults.data(forKey: UserDefaultsSettingsStore.key) != nil)
    }

    @Test func corruptDataFallsBackToDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("not json".utf8), forKey: UserDefaultsSettingsStore.key)
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == .default)
    }

    @Test func unknownProviderFallsBackToDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let json = #"{"enabledProviders":["claude","gemini"],"refreshInterval":120,"#
            + #""launchAtLogin":false,"hasCompletedOnboarding":true}"#
        defaults.set(Data(json.utf8), forKey: UserDefaultsSettingsStore.key)
        #expect(UserDefaultsSettingsStore(defaults: defaults).load() == .default)
    }

    @Test(arguments: RefreshInterval.allCases)
    func intervalTitlesAndDurations(interval: RefreshInterval) {
        #expect(interval.title.hasSuffix("minute") || interval.title.hasSuffix("minutes"))
        #expect(interval.duration == .seconds(interval.rawValue))
        #expect(interval.id == interval.rawValue)
    }

    @Test func intervalTitlesUseSingularForOneMinute() {
        #expect(RefreshInterval.oneMinute.title == "1 minute")
        #expect(RefreshInterval.fifteenMinutes.title == "15 minutes")
        #expect(RefreshInterval.default == .twoMinutes)
    }
}
