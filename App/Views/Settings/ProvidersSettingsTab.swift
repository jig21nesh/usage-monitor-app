import SwiftUI
import UsageMonitorCore

struct ProvidersSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        Form {
            Section("Show in the menu bar panel") {
                ForEach(ProviderID.allCases) { id in
                    Toggle(isOn: binding(for: id)) {
                        HStack(spacing: 8) {
                            Text(id.displayName)
                            if id.isExperimental { ExperimentalTag() }
                        }
                    }
                    .accessibilityIdentifier("settings.provider.\(id.rawValue).toggle")
                }
            }
            Section {
                Text("""
                    Grok relies on the endpoint xAI's own Grok Build CLI uses. It is the most likely of the \
                    three to change, so treat it as experimental.
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
            set: { isOn in
                var settings = model.settings
                if isOn {
                    settings.enabledProviders.insert(id)
                } else {
                    settings.enabledProviders.remove(id)
                }
                model.settings = settings
            }
        )
    }
}
