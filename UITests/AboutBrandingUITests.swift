import XCTest

/// The About window takes its publisher details from build settings (ADR 0011). Debug builds
/// accept environment overrides so the path is testable without a branded bundle.
final class AboutBrandingUITests: XCTestCase {
    @MainActor
    func testAboutShowsPublisherOverrides() {
        let app = UITestApp.launch(
            arguments: ["-openAbout"],
            environment: [
                "USAGE_MONITOR_BRAND_MAKER": "Example Publisher",
                "USAGE_MONITOR_BRAND_TAGLINE": "Example tagline for the branded build.",
                "USAGE_MONITOR_BRAND_WEBSITE": "https://example.com/publisher",
                "USAGE_MONITOR_BRAND_HOLDER": "Example Holder Pty Ltd",
            ]
        )
        defer { app.terminate() }
        let window = UITestApp.about(in: app)

        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.staticTexts["about.maker"].waitForExistence(timeout: 10))
        XCTAssertEqual(window.staticTexts["about.maker"].text, "Made by Example Publisher")
        XCTAssertEqual(window.staticTexts["about.tagline"].text, "Example tagline for the branded build.")
        XCTAssertTrue(window.staticTexts["about.legal"].text.hasPrefix("Copyright © 2026 Example Holder Pty Ltd."))
        XCTAssertTrue(window.staticTexts["about.legal"].text.contains("MIT License"))
        XCTAssertTrue(window.buttons["about.website"].exists)
        XCTAssertFalse(window.images["about.logo"].exists, "no logo asset is configured in the test build")
    }
}
