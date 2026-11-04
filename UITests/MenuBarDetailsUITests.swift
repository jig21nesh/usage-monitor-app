import XCTest

final class MenuBarDetailsUITests: XCTestCase {
    @MainActor
    func testPercentageSettingPersistsAndUsesRemainingPreference() {
        let app = UITestApp.launch(arguments: ["-openSettings"])
        XCTAssertTrue(UITestApp.waitForSettings(in: app))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Menu bar", in: app))
        let toggle = app.switches["settings.menubar.percentage"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.isOn)
        let percentageWidth = menuBarWidth(in: app)
        toggle.click()
        XCTAssertFalse(toggle.isOn)
        XCTAssertLessThan(menuBarWidth(in: app), percentageWidth, "the actual menu bar title should disappear")
        app.terminate()

        let second = UITestApp.launch(arguments: ["-openSettings"], reset: false)
        defer { second.terminate() }
        XCTAssertTrue(UITestApp.waitForSettings(in: second))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Menu bar", in: second))
        let persisted = second.switches["settings.menubar.percentage"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        XCTAssertFalse(persisted.isOn)
        let iconWidth = menuBarWidth(in: second)
        persisted.click()
        XCTAssertTrue(persisted.isOn)
        XCTAssertGreaterThan(menuBarWidth(in: second), iconWidth, "the actual menu bar title should reappear")
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Refresh", in: second))
        let style = second.popUpButtons["settings.refresh.percentStyle"]
        XCTAssertTrue(style.waitForExistence(timeout: 10))
        style.click()
        second.menuItems["Percent left"].click()
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Menu bar", in: second))
        XCTAssertTrue(second.staticTexts["settings.menubar.tracking"].text.contains("% left"))
    }

    /// Read the native item with Settings in the background, then return to its controls.
    /// This query still fails on the current macOS 27 multi-display test setup; retain the check.
    @MainActor
    private func menuBarWidth(in app: XCUIApplication) -> CGFloat {
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        defer { app.activate() }
        let item = app.statusItems["menubar.extra"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        return item.frame.width
    }

    @MainActor
    func testPanelShowsResetCountsAndExactDates() {
        let app = UITestApp.launch(arguments: ["-openPanelPreview"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)
        let count = panel.staticTexts["panel.provider.openai.resets"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        XCTAssertEqual(count.text, "2 resets available")
        XCTAssertEqual(panel.staticTexts["panel.provider.claude.resets"].text, "Available resets: not reported")
        XCTAssertFalse(panel.staticTexts["panel.provider.grok.resets"].exists)
        XCTAssertTrue(panel.staticTexts["panel.window.openai.session.resetDate"].exists)
        XCTAssertFalse(panel.staticTexts["panel.window.openai.session.resetDate"].text.isEmpty)
        XCTAssertTrue(panel.staticTexts["panel.window.openai.weekly.reset"].text.hasPrefix("Resets in 3 days"))
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = "Reset details panel"
        attachment.lifetime = .keepAlways
        add(attachment)
        let item = app.statusItems["menubar.extra"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        let menuBar = XCTAttachment(screenshot: item.screenshot())
        menuBar.name = "Menu bar percentage"
        menuBar.lifetime = .keepAlways
        add(menuBar)
    }
}
