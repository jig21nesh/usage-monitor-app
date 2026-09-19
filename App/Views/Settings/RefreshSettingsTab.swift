import SwiftUI
import UsageMonitorCore

struct RefreshSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Refresh") {
                Picker("Refresh every", selection: $model.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .accessibilityIdentifier("settings.refresh.interval")
                LabeledContent("Last refresh", value: UsageText.lastUpdated(model.lastRefreshAt))
                LabeledContent(
                    "Next refresh",
                    value: UsageText.nextRefresh(
                        after: model.lastRefreshAt,
                        interval: model.settings.refreshInterval,
                        isRefreshing: model.isRefreshing
                    )
                )
                HStack {
                    Spacer()
                    Button("Refresh now") {
                        Task { await model.refreshNow() }
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityIdentifier("settings.refresh.now")
                }
            }
            Section("Display") {
                Picker("Show percentages as", selection: $model.settings.percentStyle) {
                    ForEach(PercentStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .accessibilityIdentifier("settings.refresh.percentStyle")
            }
            Section("Startup") {
                LaunchAtLoginToggle()
            }
            Section {
                Text("""
                    Each refresh is one small read-only request per provider. Refreshing does not count \
                    against your usage limits; if a vendor rate-limits the app it backs off automatically.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
