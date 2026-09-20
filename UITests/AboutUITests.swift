import XCTest

final class AboutUITests: XCTestCase {
    @MainActor
    func testAboutWindowShowsVersionMakerAndLinks() {
        let app = UITestApp.launch(arguments: ["-openAbout"])
        defer { app.terminate() }
        let window = UITestApp.about(in: app)

        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.staticTexts["about.version"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["about.version"].text.hasPrefix("Version "))
        XCTAssertEqual(window.staticTexts["about.name"].text, "AI Usage Monitor")
        XCTAssertEqual(window.staticTexts["about.maker"].text, "Made by Curious Pi Labs")
        XCTAssertTrue(window.staticTexts["about.tagline"].text.hasPrefix("Curious Pi Labs builds products"))
        for link in ["website", "github", "issues", "license"] {
            XCTAssertTrue(window.buttons["about.\(link)"].exists, "link button \(link) should exist")
        }
        XCTAssertTrue(window.staticTexts["about.legal"].text.contains("not affiliated with or endorsed by"))
        XCTAssertTrue(window.staticTexts["about.legal"].text.contains("MIT License"))
    }

    @MainActor
    func testAboutOpensFromThePanelFooter() {
        let app = UITestApp.launch(arguments: ["-openPanelPreview"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)
        XCTAssertTrue(panel.buttons["panel.about"].waitForExistence(timeout: 15))
        panel.buttons["panel.about"].click()
        XCTAssertTrue(UITestApp.about(in: app).waitForExistence(timeout: 10))
    }
}
