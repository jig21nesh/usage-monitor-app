import SwiftUI
import UsageMonitorCore

struct AccountsSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            ForEach(model.statuses) { status in
                Section {
                    AccountRow(status: status)
                } header: {
                    HStack(spacing: 8) {
                        Text(status.provider.displayName)
                        if status.provider.isExperimental { ExperimentalTag() }
                    }
                }
            }
            Section {
                Text("""
                    AI Usage Monitor reads the login each vendor CLI already stores on this Mac, uses it for \
                    one read-only request per refresh, and never stores or sends it anywhere else. The usage \
                    endpoints are unofficial and may change without notice.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Show welcome again") {
                    AppActivation.bringToFront()
                    openWindow(id: WindowID.onboarding)
                }
                .accessibilityIdentifier("settings.showWelcome")
            }
        }
        .formStyle(.grouped)
        // Start-up probes enabled providers only; this tab shows every provider, so probe the rest here.
        .task { await model.refreshLinkStates() }
    }
}

struct AccountRow: View {
    @Environment(UsageMonitorModel.self) private var model
    let status: ProviderStatus
    @State private var isRelinking = false

    private var id: String { status.provider.rawValue }

    var body: some View {
        LabeledContent("Status") {
            LinkStateLabel(link: status.link)
                .accessibilityIdentifier("settings.account.\(id).state")
        }
        if let plan = status.snapshot?.planName ?? status.link.account?.planName {
            LabeledContent("Plan", value: plan)
        }
        LabeledContent("Source", value: status.provider.credentialOrigin)
        if let label = status.link.account?.accountLabel {
            LabeledContent("Account", value: label)
        }
        if let lastSuccess = status.lastSuccess {
            LabeledContent("Last success") {
                Text(lastSuccess, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
        }
        if let error = status.lastError {
            LabeledContent("Last error", value: error.userMessage)
        }
        LabeledContent("Sign in") {
            CopyableCommand(command: status.provider.loginCommand, identifier: "settings.account.\(id).command")
        }
        HStack {
            Spacer()
            Button {
                isRelinking = true
                Task {
                    await model.relink(status.provider)
                    isRelinking = false
                }
            } label: {
                if isRelinking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Re-link")
                }
            }
            .disabled(isRelinking)
            .accessibilityIdentifier("settings.account.\(id).relink")
        }
    }
}
