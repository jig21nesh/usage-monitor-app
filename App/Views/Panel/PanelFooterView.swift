import AppKit
import SwiftUI
import UsageMonitorCore

struct PanelFooterView: View {
    @Environment(UsageMonitorModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            Text(UsageText.lastUpdated(model.lastRefreshAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("panel.lastUpdated")
            Spacer()
            Button {
                AppActivation.bringToFront()
                openWindow(id: WindowID.about)
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About AI Usage Monitor")
            .accessibilityLabel("About")
            .accessibilityIdentifier("panel.about")
            Button {
                Task { await model.refreshNow() }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isRefreshing)
            .accessibilityIdentifier("panel.refresh")
            Button("Settings…") {
                SettingsOpener.open(using: openSettings)
            }
            .accessibilityIdentifier("panel.settings")
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .accessibilityIdentifier("panel.quit")
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
