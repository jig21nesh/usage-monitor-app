import AppKit
import SwiftUI
import UsageMonitorCore

struct MenuBarPanelView: View {
    @Environment(UsageMonitorModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.visibleStatuses.isEmpty {
                Text("No providers enabled. Choose some in Settings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.visibleStatuses) { status in
                ProviderSummaryRow(status: status)
            }
            Divider()
            HStack {
                Button("Refresh now") {
                    Task { await model.refreshNow() }
                }
                .disabled(model.isRefreshing)
                Spacer()
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 380)
    }
}

struct ProviderSummaryRow: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.provider.displayName)
                    .font(.headline)
                if let plan = status.snapshot?.planName ?? status.link.account?.planName {
                    Text(plan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if status.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else if status.isStale {
                    Text("stale").font(.caption).foregroundStyle(.orange)
                }
            }
            if let snapshot = status.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageBarRow(window: window)
                }
            } else {
                Text(status.lastError?.userMessage ?? linkMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var linkMessage: String {
        switch status.link {
        case .unknown: "Checking…"
        case .linked: "Waiting for first refresh…"
        case .notLinked(let error): "\(error.userMessage) Run `\(status.provider.loginCommand)`."
        }
    }
}

struct UsageBarRow: View {
    let window: UsageWindow

    var body: some View {
        HStack {
            Text(window.title)
                .frame(width: 120, alignment: .leading)
            ProgressView(value: window.usedPercent, total: 100)
            Text("\(Int(window.usedPercent.rounded()))% used")
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .font(.callout)
    }
}
