import XCTest

final class SettingsUITests: XCTestCase {
    @MainActor
    func testSettingsHasFourTabsAndProviderToggleHidesPanelSection() {
        let app = UITestApp.launch(arguments: ["-openPanelPreview", "-openSettings"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)

        XCTAssertTrue(panel.staticTexts["panel.provider.grok.name"].waitForExistence(timeout: 15))
        XCTAssertTrue(UITestApp.waitForSettings(in: app))

        for tab in ["Providers", "Refresh", "Diagnostics", "Accounts"] {
            XCTAssertTrue(UITestApp.selectSettingsTab(named: tab, in: app), "tab \(tab) should be selectable")
        }
        XCTAssertTrue(app.buttons["settings.showWelcome"].waitForExistence(timeout: 5))

        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Providers", in: app))
        let grokToggle = app.switches["settings.provider.grok.toggle"]
        XCTAssertTrue(grokToggle.waitForExistence(timeout: 10))
        XCTAssertTrue(grokToggle.isOn)
        grokToggle.click()

        XCTAssertTrue(UITestApp.waitForDisappearance(of: panel.staticTexts["panel.provider.grok.name"]))
        XCTAssertTrue(panel.staticTexts["panel.provider.claude.name"].exists)
        XCTAssertFalse(grokToggle.isOn)
    }

    @MainActor
    func testRefreshIntervalPersistsAcrossLaunches() {
        let first = UITestApp.launch(arguments: ["-openSettings"], reset: true)
        XCTAssertTrue(UITestApp.waitForSettings(in: first))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Refresh", in: first))

        let picker = first.popUpButtons["settings.refresh.interval"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.value as? String, "2 minutes")
        XCTAssertTrue(first.switches["settings.launchAtLogin"].exists)
        picker.click()
        let option = first.menuItems["5 minutes"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.click()
        XCTAssertEqual(picker.value as? String, "5 minutes")
        first.terminate()

        let second = UITestApp.launch(arguments: ["-openSettings"], reset: false)
        defer { second.terminate() }
        XCTAssertTrue(UITestApp.waitForSettings(in: second))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Refresh", in: second))
        let persisted = second.popUpButtons["settings.refresh.interval"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        XCTAssertEqual(persisted.value as? String, "5 minutes")
    }

    @MainActor
    func testDiagnosticsTabShowsCountersAndVersion() {
        let app = UITestApp.launch(arguments: ["-openSettings"])
        defer { app.terminate() }
        XCTAssertTrue(UITestApp.waitForSettings(in: app))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Diagnostics", in: app))
        let table = app.outlines["settings.diagnostics.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        XCTAssertEqual(table.outlineRows.count, 3)

        let claudeCell = table.staticTexts.matching(NSPredicate(format: "value == 'Claude' OR label == 'Claude'"))
        XCTAssertTrue(claudeCell.firstMatch.waitForExistence(timeout: 5))
        let versionPredicate = NSPredicate(format: "value BEGINSWITH 'App ' OR label BEGINSWITH 'App '")
        XCTAssertTrue(app.staticTexts.matching(versionPredicate).firstMatch.exists)
    }

    /// Skipped: the initially selected tab's form content is not exposed to accessibility until a
    /// tab is re-selected on macOS 27.0 / Xcode 26.6. Tracked in https://github.com/jig21nesh/usage-monitor-app/issues/10.
    @MainActor
    func testAccountsTabContentIsQueryableAtLaunch() throws {
        throw XCTSkip("Accounts form content not exposed at launch on macOS 27; see https://github.com/jig21nesh/usage-monitor-app/issues/10")
    }
}
