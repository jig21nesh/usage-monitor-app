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
        #expect(settings.enabledProviders == Set(ProviderID.defaultEnabled))
        #expect(settings.menuBarProvider == nil)
        #expect(settings.menuBarThresholds == .default)
        #expect(settings.colorsMenuBarIcon)
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

    @Test func unknownProviderIsDroppedNotFatal() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let json = #"{"enabledProviders":["claude","gemini"],"refreshInterval":120,"#
            + #""launchAtLogin":false,"hasCompletedOnboarding":true}"#
        defaults.set(Data(json.utf8), forKey: UserDefaultsSettingsStore.key)
        let loaded = UserDefaultsSettingsStore(defaults: defaults).load()
        #expect(loaded.enabledProviders == [.claude])
        #expect(loaded.hasCompletedOnboarding)
        #expect(loaded.menuBarThresholds == .default)
    }

    @Test func menuBarKeysRoundTripAndDefaultWhenAbsent() throws {
        var settings = AppSettings.default
        settings.menuBarProvider = .openAI
        settings.menuBarThresholds = MenuBarThresholds(warningPercent: 50, criticalPercent: 75)
        settings.colorsMenuBarIcon = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)

        let legacy = #"{"enabledProviders":["grok"],"refreshInterval":300,"launchAtLogin":true,"#
            + #""hasCompletedOnboarding":true,"percentStyle":"remaining"}"#
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(old.menuBarProvider == nil)
        #expect(old.menuBarThresholds == .default)
        #expect(old.colorsMenuBarIcon)
        #expect(old.percentStyle == .remaining)
    }

    @Test func thresholdsAreClampedAndOrdered() {
        let swapped = MenuBarThresholds(warningPercent: 90, criticalPercent: 40)
        #expect(swapped.warningPercent == 40)
        #expect(swapped.criticalPercent == 90)
        let wild = MenuBarThresholds(warningPercent: -5, criticalPercent: 250)
        #expect(wild.warningPercent == 0)
        #expect(wild.criticalPercent == 100)
        #expect(MenuBarThresholds(warningPercent: .nan, criticalPercent: 80).warningPercent == 0)
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
