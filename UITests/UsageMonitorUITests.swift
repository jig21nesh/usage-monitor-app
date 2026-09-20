import XCTest

final class UsageMonitorUITests: XCTestCase {
    @MainActor
    func testAppLaunchesAsBackgroundMenuBarExtra() {
        let app = UITestApp.launch()
        defer { app.terminate() }
        let isRunning = app.wait(for: .runningBackground, timeout: 15) || app.state == .runningForeground
        XCTAssertTrue(isRunning, "app should stay running as a menu bar extra")
    }

    @MainActor
    func testPanelShowsLinkedProvidersWithScreenshotNumbers() {
        let app = UITestApp.launch(arguments: ["-openPanelPreview"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)

        XCTAssertTrue(panel.staticTexts["panel.provider.claude.name"].waitForExistence(timeout: 15))
        XCTAssertTrue(panel.staticTexts["panel.provider.openai.name"].exists)
        XCTAssertTrue(panel.staticTexts["panel.provider.grok.name"].exists)
        XCTAssertTrue(panel.staticTexts["panel.provider.copilot.name"].exists)
        XCTAssertTrue(panel.staticTexts["panel.provider.muse.name"].exists)
        XCTAssertFalse(panel.staticTexts["panel.provider.cursor.name"].exists, "not-linked providers start off")

        XCTAssertTrue(panel.staticTexts["panel.window.claude.session.percent"].waitForExistence(timeout: 10))
        XCTAssertEqual(panel.staticTexts["panel.window.claude.session.percent"].text, "0% used")
        XCTAssertEqual(panel.staticTexts["panel.window.claude.weekly.all.percent"].text, "29% used")
        XCTAssertEqual(panel.staticTexts["panel.window.claude.weekly.fable.percent"].text, "56% used")
        XCTAssertEqual(panel.staticTexts["panel.window.openai.weekly.percent"].text, "58% used")
        XCTAssertEqual(panel.staticTexts["panel.window.grok.weekly.percent"].text, "4% used")
        XCTAssertEqual(panel.staticTexts["panel.window.copilot.monthly.percent"].text, "40% used")
        XCTAssertEqual(panel.staticTexts["panel.window.muse.session.percent"].text, "12% used")
        XCTAssertEqual(panel.staticTexts["panel.window.muse.weekly.percent"].text, "30% used")

        XCTAssertTrue(panel.staticTexts["panel.window.claude.session.reset"].text.hasPrefix("Resets in 4 hr"))
        XCTAssertTrue(panel.staticTexts["panel.window.claude.weekly.all.reset"].text.hasPrefix("Resets "))
        XCTAssertTrue(panel.staticTexts["panel.provider.claude.plan"].text.hasSuffix("Max (20x)"))
        XCTAssertTrue(panel.staticTexts["panel.lastUpdated"].text.hasPrefix("Updated "))
        XCTAssertTrue(panel.buttons["panel.refresh"].exists)
        XCTAssertTrue(panel.buttons["panel.settings"].exists)
        XCTAssertTrue(panel.buttons["panel.about"].exists)
        XCTAssertTrue(panel.buttons["panel.quit"].exists)
    }

    @MainActor
    func testNotLinkedScenarioShowsLoginCommandAndRelink() {
        let app = UITestApp.launch(scenario: .notLinked, arguments: ["-openPanelPreview"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)

        XCTAssertTrue(panel.staticTexts["panel.provider.claude.loginCommand"].waitForExistence(timeout: 15))
        XCTAssertEqual(panel.staticTexts["panel.provider.claude.loginCommand"].text, "claude login")
        XCTAssertTrue(panel.buttons["panel.provider.claude.relink"].exists)
        XCTAssertTrue(panel.buttons["panel.provider.claude.loginCommand.copy"].exists)
        XCTAssertFalse(panel.staticTexts["panel.window.claude.session.percent"].exists)
        XCTAssertEqual(panel.staticTexts["panel.provider.openai.loginCommand"].text, "codex login")
        XCTAssertFalse(panel.staticTexts["panel.window.openai.weekly.percent"].exists)
    }

    @MainActor
    func testStaleScenarioKeepsNumbersAndFlagsStale() {
        let app = UITestApp.launch(scenario: .stale, arguments: ["-openPanelPreview"])
        defer { app.terminate() }
        let panel = UITestApp.panel(in: app)

        XCTAssertTrue(panel.staticTexts["panel.provider.claude.error"].waitForExistence(timeout: 15))
        XCTAssertEqual(panel.staticTexts["panel.window.claude.weekly.fable.percent"].text, "56% used")
        XCTAssertTrue(panel.staticTexts["Stale"].exists)
    }

    @MainActor
    func testOnboardingAppearsOnFirstLaunchAndDoneDismissesIt() {
        let app = UITestApp.launch(firstLaunch: true)
        defer { app.terminate() }
        let window = UITestApp.onboarding(in: app)

        XCTAssertTrue(window.waitForExistence(timeout: 15))
        XCTAssertTrue(window.staticTexts["onboarding.provider.claude.command"].waitForExistence(timeout: 10))
        XCTAssertEqual(window.staticTexts["onboarding.provider.claude.command"].text, "claude login")
        XCTAssertTrue(window.buttons["onboarding.provider.claude.recheck"].exists)
        XCTAssertTrue(window.checkBoxes["onboarding.provider.grok.toggle"].exists)
        XCTAssertTrue(window.checkBoxes["settings.launchAtLogin"].exists)

        window.buttons["onboarding.done"].click()
        XCTAssertTrue(UITestApp.waitForDisappearance(of: window))
    }

    @MainActor
    func testOnboardingFirstLaunchEnablesDetectedProviders() {
        let app = UITestApp.launch(firstLaunch: true, reset: true)
        defer { app.terminate() }
        let window = UITestApp.onboarding(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        for provider in UITestApp.allProviders {
            XCTAssertTrue(
                window.checkBoxes["onboarding.provider.\(provider).toggle"].waitForExistence(timeout: 10),
                "card for \(provider) should exist"
            )
        }
        for provider in UITestApp.linkedProviders {
            XCTAssertTrue(
                UITestApp.waitForSwitch(window.checkBoxes["onboarding.provider.\(provider).toggle"], toBe: true),
                "\(provider) is linked and should be switched on"
            )
        }
        for provider in ["cursor", "opencode-go"] {
            XCTAssertTrue(
                UITestApp.waitForSwitch(window.checkBoxes["onboarding.provider.\(provider).toggle"], toBe: false),
                "\(provider) is not linked and should stay off"
            )
        }

        window.buttons["onboarding.done"].click()
        XCTAssertTrue(UITestApp.waitForDisappearance(of: window))

        // Relaunch without reset: the detected set must have been persisted.
        app.terminate()
        let second = UITestApp.launch(arguments: ["-openSettings"], reset: false)
        defer { second.terminate() }
        XCTAssertTrue(UITestApp.waitForSettings(in: second))
        XCTAssertTrue(UITestApp.selectSettingsTab(named: "Providers", in: second))
        for provider in UITestApp.linkedProviders {
            let toggle = second.switches["settings.provider.\(provider).toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            XCTAssertTrue(toggle.isOn, "\(provider) should be on after onboarding")
        }
        for provider in ["cursor", "opencode-go"] {
            XCTAssertFalse(second.switches["settings.provider.\(provider).toggle"].isOn, "\(provider) should be off")
        }
    }
}
