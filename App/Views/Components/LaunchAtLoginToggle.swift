import SwiftUI
import UsageMonitorCore

/// Launch-at-login control shared by onboarding and Settings. Failures stay inline and the
/// setting reverts, so the UI never claims a state the system did not accept.
struct LaunchAtLoginToggle: View {
    @Environment(UsageMonitorModel.self) private var model
    @State private var errorMessage: String?

    private var loginItems: any LoginItemControlling { AppComposition.loginItems }

    var body: some View {
        Toggle("Launch at login", isOn: binding)
            .accessibilityIdentifier("settings.launchAtLogin")
        if loginItems.requiresApproval {
            HStack {
                Text("macOS needs your approval before the app can launch at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items…") {
                    loginItems.openSystemSettings()
                }
                .accessibilityIdentifier("settings.launchAtLogin.approve")
            }
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.launchAtLogin.error")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { model.settings.launchAtLogin },
            set: { apply($0) }
        )
    }

    private func apply(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            model.settings.launchAtLogin = enabled
            errorMessage = nil
        } catch {
            model.settings.launchAtLogin = loginItems.isEnabled
            errorMessage = "Could not update the login item: \(error.localizedDescription)"
        }
    }
}
