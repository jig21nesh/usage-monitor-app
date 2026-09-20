import SwiftUI
import UsageMonitorCore

struct ProvidersSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        Form {
            Section("Show in the menu bar panel") {
                ForEach(model.statuses) { status in
                    Toggle(isOn: binding(for: status.provider)) {
                        HStack(spacing: 8) {
                            Text(status.provider.displayName)
                            if status.provider.isExperimental { ExperimentalTag() }
                        }
                    }
                    .accessibilityIdentifier("settings.provider.\(status.provider.rawValue).toggle")
                }
            }
            Section {
                Text("""
                    Providers marked Experimental rely on the newest or least documented vendor endpoints, \
                    so they are the most likely to change or pause without notice.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: ProviderID) -> Binding<Bool> {
        Binding(
            get: { model.settings.enabledProviders.contains(id) },
            set: { model.setEnabled(id, $0) }
        )
    }
}
