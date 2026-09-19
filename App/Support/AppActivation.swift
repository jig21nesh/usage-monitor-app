import AppKit

enum WindowID {
    static let onboarding = "onboarding"
    static let panelPreview = "panel-preview"
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
