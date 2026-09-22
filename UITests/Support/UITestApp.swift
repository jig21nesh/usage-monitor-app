import XCTest

enum UITestScenario: String {
    case linked
    case notLinked
    case stale
}

/// Launches the app in deterministic UI-test mode (fake providers, throwaway defaults).
enum UITestApp {
    static let settingsWindowID = "com_apple_SwiftUI_Settings_window"
    static let panelPreviewTitle = "Panel Preview"
    static let onboardingTitle = "Welcome to AI Usage Monitor"
    static let aboutTitle = "About AI Usage Monitor"
    static let allProviders = ["claude", "openai", "grok", "copilot", "cursor", "muse", "opencode-go"]
    static let linkedProviders = ["claude", "openai", "grok", "copilot", "muse"]

    @MainActor
    static func launch(
        scenario: UITestScenario = .linked,
        arguments: [String] = [],
        firstLaunch: Bool = false,
        reset: Bool = true,
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment.merge(environment) { _, override in override }
        app.launchEnvironment["USAGE_MONITOR_UITEST"] = "1"
        app.launchEnvironment["USAGE_MONITOR_UITEST_SCENARIO"] = scenario.rawValue
        if firstLaunch {
            app.launchEnvironment["USAGE_MONITOR_UITEST_FIRST_LAUNCH"] = "1"
        }
        if reset {
            app.launchEnvironment["USAGE_MONITOR_UITEST_RESET"] = "1"
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// The menu bar extra's own content is also in the tree, so panel queries scope to the preview window.
    @MainActor
    static func panel(in app: XCUIApplication) -> XCUIElement {
        app.windows[panelPreviewTitle]
    }

    @MainActor
    static func settings(in app: XCUIApplication) -> XCUIElement {
        app.windows[settingsWindowID]
    }

    @MainActor
    static func onboarding(in app: XCUIApplication) -> XCUIElement {
        app.windows[onboardingTitle]
    }

    @MainActor
    static func about(in app: XCUIApplication) -> XCUIElement {
        app.windows[aboutTitle]
    }

    /// Waits until a switch reports the wanted state, for values that settle asynchronously.
    @MainActor
    static func waitForSwitch(_ element: XCUIElement, toBe wanted: Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isOn == wanted { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isOn == wanted
    }

    /// The Settings toolbar is queryable as soon as the window exists; the initially selected
    /// tab's form content is not (see the skipped `testAccountsTabContentIsQueryableAtLaunch`).
    @MainActor
    static func waitForSettings(in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        settings(in: app).buttons["Accounts"].waitForExistence(timeout: timeout)
    }

    /// Settings tabs are toolbar buttons titled after the tab. A coordinate click is the fallback
    /// when the hit test fails, which happens when the window sits on a secondary display.
    @MainActor
    static func selectSettingsTab(named name: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let button = settings(in: app).buttons[name]
        guard button.waitForExistence(timeout: timeout) else { return false }
        if button.isHittable {
            button.click()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        return true
    }

    @MainActor
    static func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// macOS exposes SwiftUI `Text` through `value`; `label` is usually empty.
    var text: String {
        if let value = value as? String, !value.isEmpty { return value }
        return label
    }

    /// Switches and check boxes report their state as a number, occasionally as a string.
    var isOn: Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return string == "1" || string.lowercased() == "on" }
        return false
    }
}
