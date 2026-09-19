import XCTest

final class UsageMonitorUITests: XCTestCase {
    func testAppLaunchesAsBackgroundMenuBarExtra() {
        let app = XCUIApplication()
        app.launchEnvironment["USAGE_MONITOR_UITEST"] = "1"
        app.launch()
        let isRunning = app.wait(for: .runningBackground, timeout: 15) || app.state == .runningForeground
        XCTAssertTrue(isRunning, "app should stay running as a menu bar extra")
        app.terminate()
    }
}
