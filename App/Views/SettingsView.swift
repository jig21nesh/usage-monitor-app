import SwiftUI
import UsageMonitorCore

struct SettingsView: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                ForEach(ProviderID.allCases) { id in
                    Toggle(isOn: binding(for: id)) {
                        Text(id.displayName + (id.isExperimental ? " (experimental)" : ""))
                    }
                }
            }
            .tabItem { Label("Providers", systemImage: "list.bullet") }

            Form {
                Picker("Refresh every", selection: $model.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
            }
            .tabItem { Label("Refresh", systemImage: "clock.arrow.2.circlepath") }

            Form {
                ForEach(model.statuses) { status in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(status.provider.displayName).font(.headline)
                            Text(accountText(status)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Re-link") {
                            Task { await model.relink(status.provider) }
                        }
                    }
                }
            }
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
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

    private func accountText(_ status: ProviderStatus) -> String {
        switch status.link {
        case .unknown: "Not checked yet"
        case .linked(let info): "Linked via \(info.origin)" + (info.planName.map { " · \($0)" } ?? "")
        case .notLinked(let error): error.userMessage
        }
    }
}
