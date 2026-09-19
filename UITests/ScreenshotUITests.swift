import XCTest

/// Captures documentation screenshots as result-bundle attachments. Skipped unless the runner
/// environment sets `SCREENSHOTS=1` (pass `TEST_RUNNER_SCREENSHOTS=1` to xcodebuild); export
/// them with `xcrun xcresulttool export attachments`.
final class ScreenshotUITests: XCTestCase {
    @MainActor
    func testCaptureDocumentationScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1", "SCREENSHOTS not set")

        let app = UITestApp.launch(arguments: ["-openPanelPreview", "-openSettings", "-openOnboarding"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)
        let onboarding = UITestApp.onboarding(in: app)
        let settings = UITestApp.settings(in: app)
        XCTAssertTrue(panel.staticTexts["panel.window.claude.session.percent"].waitForExistence(timeout: 15))
        XCTAssertTrue(onboarding.staticTexts["onboarding.provider.claude.command"].waitForExistence(timeout: 15))
        XCTAssertTrue(UITestApp.waitForSettings(in: app))

        attach(panel, as: "panel")
        attach(onboarding, as: "onboarding")
        attach(settings, as: "settings-accounts")
        if UITestApp.selectSettingsTab(named: "Refresh", in: app) {
            _ = app.popUpButtons["settings.refresh.interval"].waitForExistence(timeout: 5)
            attach(settings, as: "settings-refresh")
        }
    }

    @MainActor
    private func attach(_ element: XCUIElement, as name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
