import Foundation
import UsageMonitorCore

/// The app's single composition root (ADR 0001). Views receive the model through the environment.
enum AppComposition {
    static let launchOptions = LaunchOptions.parse()
    static let model = makeModel(options: launchOptions)
    static let loginItems: any LoginItemControlling = makeLoginItems(options: launchOptions)

    static func makeModel(options: LaunchOptions) -> UsageMonitorModel {
        #if DEBUG
        if options.isUITesting {
            return PreviewComposition.makeModel(options: options)
        }
        #endif
        return UsageMonitorModel(
            providers: ProviderRegistry.live(),
            settingsStore: UserDefaultsSettingsStore(),
            wakeSource: WorkspaceWakeSource()
        )
    }

    static func makeLoginItems(options: LaunchOptions) -> any LoginItemControlling {
        options.isUITesting ? FakeLoginItemController() : SMAppServiceLoginItemController()
    }
}
