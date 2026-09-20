import AppKit
import SwiftUI

enum WindowID {
    static let onboarding = "onboarding"
    static let panelPreview = "panel-preview"
    static let about = "about"
}

/// An `LSUIElement` app has no Dock icon and cannot bring a window to the front on its own.
/// While a regular window is open the app temporarily becomes a regular app; it drops back to
/// accessory when the last such window closes.
enum AppActivation {
    static func bringToFront() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    /// SwiftUI opens windows on the Space and display that hold the pointer, which on a
    /// multi-display Mac can be a Space the user is not looking at. Tagging the window with
    /// `moveToActiveSpace` makes it follow the user instead. Ordering is left alone: reordering
    /// windows here steals focus from whichever one the user or a UI test just opened.
    static func followActiveSpace() {
        let regular = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.level == .normal }
        for window in regular {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    /// Opens a SwiftUI window scene, brings the app forward and lets the window follow the
    /// user's current Space.
    static func open(_ id: String, using openWindow: OpenWindowAction) {
        bringToFront()
        openWindow(id: id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            followActiveSpace()
        }
    }

    static func returnToAccessoryIfNoWindows(excluding closing: NSWindow? = nil) {
        let hasRegularWindow = NSApp.windows.contains { window in
            window !== closing && window.isVisible && window.styleMask.contains(.titled) && window.level == .normal
        }
        if !hasRegularWindow, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// SwiftUI titles the Settings window after the selected tab, so match its stable identifier.
    static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    static var hasSettingsWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue == settingsWindowIdentifier }
    }
}
