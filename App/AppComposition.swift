import Foundation
import UsageMonitorCore

/// The app's single composition root (ADR 0001). Views receive the model through the environment.
enum AppComposition {
    static let model = makeModel()

    static func makeModel() -> UsageMonitorModel {
        UsageMonitorModel(
            providers: ProviderRegistry.live(),
            settingsStore: UserDefaultsSettingsStore()
        )
    }
}
