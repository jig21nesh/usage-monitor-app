import XCTest

/// The sandbox grant step (ADR 0009). UI-test builds answer the folder picker with a fake.
final class HomeFolderAccessUITests: XCTestCase {
    @MainActor
    func testOnboardingGrantButtonFlipsTheStateToGranted() {
        let app = UITestApp.launch(firstLaunch: true)
        defer { app.terminate() }
        let window = UITestApp.onboarding(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let state = window.staticTexts["onboarding.homeFolder.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertEqual(state.text, "Not granted")
        let grant = window.buttons["onboarding.homeFolder.grant"]
        XCTAssertTrue(grant.exists)

        grant.click()

        let granted = NSPredicate(format: "value BEGINSWITH 'Granted' OR label BEGINSWITH 'Granted'")
        let expectation = XCTNSPredicateExpectation(predicate: granted, object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed)
        XCTAssertTrue(state.text.hasSuffix("/Users/you"))
        XCTAssertFalse(window.buttons["onboarding.homeFolder.grant"].exists, "granted state hides the button")
        XCTAssertFalse(window.staticTexts["onboarding.homeFolder.error"].exists)
    }

    @MainActor
    func testDiagnosticsFooterShowsTheGrantState() {
        let app = UITestApp.launch(arguments: ["-openSettings"])
        defer { app.terminate() }
        XCTAssertTrue(UITestApp.waitForSettings(in: app))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Diagnostics", in: app))

        // The footer texts are exposed by value, like the version line the settings test reads.
        let predicate = NSPredicate(
            format: "value BEGINSWITH 'Home folder access:' OR label BEGINSWITH 'Home folder access:'"
        )
        let line = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        XCTAssertEqual(line.text, "Home folder access: Granted")
    }
}
