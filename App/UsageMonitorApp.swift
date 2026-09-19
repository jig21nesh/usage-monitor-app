import AppKit
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
            Label("AI Usage Monitor", systemImage: "gauge.with.dots.needle.33percent")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Starts and stops the poll loop with the process, independent of any window being open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppComposition.model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppComposition.model.stop()
    }
}
