import AppKit
import SwiftUI
import UsageMonitorCore

/// Opens Settings from an accessory app. Tahoe builds have needed the app activated first, and
/// early betas ignored `openSettings` entirely, hence the selector fallback.
enum SettingsOpener {
    static func open(using openSettings: OpenSettingsAction) {
        AppActivation.bringToFront()
        openSettings()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            let opened = AppActivation.hasSettingsWindow
            UsageLog.polling.notice("settings open via environment action=\(opened, privacy: .public)")
            guard !opened else { return }
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// Decides which windows to show right after launch: onboarding on first run, plus whatever the
/// debug launch arguments ask for. The scene tree is not ready on the label's first render, so
/// the actions are retried briefly until a window actually appears.
enum StartupRouter {
    static func route(
        _ options: LaunchOptions,
        model: UsageMonitorModel,
        openWindow: OpenWindowAction,
        openSettings: OpenSettingsAction
    ) async {
        let wantsOnboarding = options.openOnboarding || !model.settings.hasCompletedOnboarding
        // swiftlint:disable:next line_length
        UsageLog.polling.notice("startup route panelPreview=\(options.openPanelPreview, privacy: .public) onboarding=\(wantsOnboarding, privacy: .public) settings=\(options.openSettings, privacy: .public)")
        for attempt in 0..<10 {
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 300 : 700))
            #if DEBUG
            if options.openPanelPreview {
                AppActivation.bringToFront()
                openWindow(id: WindowID.panelPreview)
            }
            #endif
            if wantsOnboarding {
                AppActivation.bringToFront()
                openWindow(id: WindowID.onboarding)
            }
            if options.openSettings {
                SettingsOpener.open(using: openSettings)
            }
            if options.openAbout {
                AppActivation.bringToFront()
                openWindow(id: WindowID.about)
            }
            try? await Task.sleep(for: .milliseconds(400))
            if options.isUITesting {
                moveWindowsToPrimaryScreen()
            } else {
                AppActivation.followActiveSpace()
            }
            let titles = NSApp.windows.filter(\.isVisible).map(\.title).joined(separator: "|")
            UsageLog.polling.notice("startup attempt=\(attempt, privacy: .public) windows=\(titles, privacy: .public)")
            let wantsAnything = options.openPanelPreview || wantsOnboarding || options.openSettings || options.openAbout
            if !titles.isEmpty || !wantsAnything {
                return
            }
        }
    }

    /// UI tests click by screen coordinates. On a multi-display Mac SwiftUI centres new windows on
    /// whichever screen holds the pointer, where they may be covered or off the primary display,
    /// so in test mode every window is parked on the primary screen instead.
    private static func moveWindowsToPrimaryScreen() {
        guard let primary = NSScreen.screens.first else { return }
        var offset: CGFloat = 0
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            let frame = window.frame
            let origin = CGPoint(
                x: primary.visibleFrame.minX + 40 + offset,
                y: primary.visibleFrame.maxY - frame.height - 40 - offset
            )
            window.setFrameOrigin(origin)
            offset += 32
        }
    }
}
