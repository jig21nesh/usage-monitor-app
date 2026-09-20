import Foundation

/// Parsed once at startup. Every switch here is ignored in Release builds so a shipped binary
/// cannot be steered into test mode.
struct LaunchOptions: Equatable {
    enum Scenario: String {
        case linked
        case notLinked
        case stale
    }

    var isUITesting = false
    var scenario: Scenario = .linked
    var firstLaunch = false
    var resetDefaults = false
    var openSettings = false
    var openOnboarding = false
    var openPanelPreview = false
    var openAbout = false

    static func parse(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchOptions {
        var options = LaunchOptions()
        #if DEBUG
        options.isUITesting = environment["USAGE_MONITOR_UITEST"] == "1" || arguments.contains("-uiTesting")
        options.scenario = environment["USAGE_MONITOR_UITEST_SCENARIO"].flatMap(Scenario.init(rawValue:)) ?? .linked
        options.firstLaunch = environment["USAGE_MONITOR_UITEST_FIRST_LAUNCH"] == "1"
        options.resetDefaults = environment["USAGE_MONITOR_UITEST_RESET"] == "1"
        options.openSettings = arguments.contains("-openSettings")
        options.openOnboarding = arguments.contains("-openOnboarding")
        options.openPanelPreview = arguments.contains("-openPanelPreview")
        options.openAbout = arguments.contains("-openAbout")
        #endif
        return options
    }
}
