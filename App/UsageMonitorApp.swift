import SwiftUI
import UsageMonitorCore

@main
struct UsageMonitorApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    private var model: UsageMonitorModel { AppComposition.model }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }

        Window("Welcome to AI Usage Monitor", id: WindowID.onboarding) {
            OnboardingView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        #if DEBUG
        Window("Panel Preview", id: WindowID.panelPreview) {
            MenuBarPanelView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        #endif
    }
}
