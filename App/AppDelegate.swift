import AppKit
import UsageMonitorCore

/// Starts and stops the poll loop with the process and keeps the app out of the Dock whenever
/// no regular window is open (ADR 0001).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = AppComposition.launchOptions
        let model = AppComposition.model
        reconcileLaunchAtLogin(with: model)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            let closing = notification.object as? NSWindow
            Task { @MainActor in
                AppActivation.returnToAccessoryIfNoWindows(excluding: closing)
            }
        }
        if options.isUITesting {
            #if DEBUG
            Task { await PreviewComposition.warmUp(model, scenario: options.scenario) }
            #endif
        } else {
            model.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppComposition.model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The system is the source of truth for login items; settings only mirror it.
    private func reconcileLaunchAtLogin(with model: UsageMonitorModel) {
        let enabled = AppComposition.loginItems.isEnabled
        if model.settings.launchAtLogin != enabled {
            model.settings.launchAtLogin = enabled
        }
    }
}
