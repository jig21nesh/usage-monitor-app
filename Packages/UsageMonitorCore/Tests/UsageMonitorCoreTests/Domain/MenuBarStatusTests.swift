import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("MenuBarStatusResolver")
struct MenuBarStatusTests {
    let thresholds = MenuBarThresholds.default

    private func status(
        _ id: ProviderID,
        enabled: Bool = true,
        session: Double? = nil,
        weekly: Double? = nil,
        error: ProviderError? = nil
    ) -> ProviderStatus {
        var windows: [UsageWindow] = []
        if let session {
            windows.append(
                UsageWindow(id: "\(id.rawValue).session", title: "Session", kind: .session, usedPercent: session)
            )
        }
        if let weekly {
            windows.append(
                UsageWindow(id: "\(id.rawValue).weekly", title: "Weekly", kind: .weekly, usedPercent: weekly)
            )
        }
        let snapshot = windows.isEmpty
            ? nil
            : UsageSnapshot(provider: id, planName: nil, windows: windows, fetchedAt: .now)
        return ProviderStatus(provider: id, isEnabled: enabled, snapshot: snapshot, lastError: error)
    }

    private func settings(provider: ProviderID? = nil, enabled: Set<ProviderID>) -> AppSettings {
        var settings = AppSettings.default
        settings.enabledProviders = enabled
        settings.menuBarProvider = provider
        return settings
    }

    @Test(arguments: [
        (0.0, MenuBarLevel.ok), (59.9, .ok), (60.0, .warning), (79.9, .warning), (80.0, .critical), (100.0, .critical),
    ])
    func levelsFollowThresholds(percent: Double, expected: MenuBarLevel) {
        #expect(MenuBarStatusResolver.level(forPercent: percent, thresholds: thresholds) == expected)
    }

    @Test func missingOrNonFinitePercentIsUnknown() {
        #expect(MenuBarStatusResolver.level(forPercent: nil, thresholds: thresholds) == .unknown)
        #expect(MenuBarStatusResolver.level(forPercent: .nan, thresholds: thresholds) == .unknown)
    }

    @Test func trackedWindowPrefersSessionThenFullest() {
        let both = status(.claude, session: 10, weekly: 90).snapshot!
        #expect(MenuBarStatusResolver.trackedWindow(in: both)?.kind == .session)
        let weeklyOnly = status(.grok, weekly: 42).snapshot!
        #expect(MenuBarStatusResolver.trackedWindow(in: weeklyOnly)?.usedPercent == 42)
    }

    @Test func chosenProviderWins() {
        let statuses = [status(.claude, session: 95), status(.openAI, session: 10)]
        let chosen = settings(provider: .openAI, enabled: [.claude, .openAI])
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: chosen)
        #expect(result.provider == .openAI)
        #expect(result.level == .ok)
    }

    @Test func singleEnabledProviderIsUsedWithoutAChoice() {
        let statuses = [status(.claude, enabled: false, session: 95), status(.grok, weekly: 65)]
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: settings(enabled: [.grok]))
        #expect(result.provider == .grok)
        #expect(result.level == .warning)
    }

    @Test func automaticModePicksTheFullestSessionWindow() {
        let statuses = [status(.claude, session: 30), status(.openAI, session: 85), status(.grok, weekly: 99)]
        let all = settings(enabled: [.claude, .openAI, .grok])
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: all)
        #expect(result.provider == .grok)
        #expect(result.level == .critical)
    }

    @Test func disabledChoiceFallsBackToAutomatic() {
        let statuses = [
            status(.claude, enabled: false, session: 5), status(.openAI, session: 70), status(.grok, session: 20),
        ]
        let chosen = settings(provider: .claude, enabled: [.openAI, .grok])
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: chosen)
        #expect(result.provider == .openAI)
        #expect(result.level == .warning)
    }

    @Test func noSnapshotsMeansUnknown() {
        let statuses = [status(.claude), status(.openAI)]
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: settings(enabled: [.claude, .openAI]))
        #expect(result == .unknown)
        #expect(MenuBarStatusResolver.resolve(statuses: [], settings: settings(enabled: [])) == .unknown)
    }

    @Test func staleFlagAndLevelSurviveTogether() {
        let statuses = [status(.claude, session: 61, error: .network("x"))]
        let result = MenuBarStatusResolver.resolve(statuses: statuses, settings: settings(enabled: [.claude]))
        #expect(result.isStale)
        #expect(result.level == .warning)
        #expect(result.window?.usedPercent == 61)
    }
}
