import SwiftUI
import UsageMonitorCore

/// First-run window. Explains the credential model (ADR 0002) and lets the user link providers.
struct OnboardingView: View {
    @Environment(UsageMonitorModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ForEach(model.statuses) { status in
                        OnboardingProviderCard(status: status)
                    }
                    howItWorks
                    GroupBox("Startup") {
                        VStack(alignment: .leading, spacing: 6) {
                            LaunchAtLoginToggle()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("You can change all of this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.done")
            }
            .padding()
        }
        .frame(width: 640, height: 640)
        .task { await model.refreshLinkStates() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to AI Usage Monitor")
                .font(.largeTitle.weight(.semibold))
            Text("""
                See how much of your Claude, OpenAI and Grok subscription limits you have used, \
                right from the menu bar.
                """)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var howItWorks: some View {
        GroupBox("How this works, and what it never does") {
            VStack(alignment: .leading, spacing: 6) {
                bullet("It reads the login that Claude Code, Codex CLI and Grok Build CLI already store on this Mac.")
                bullet("Each refresh makes one read-only request per provider with that login. "
                    + "Polling does not consume your quota.")
                bullet("It never stores, refreshes or transmits your tokens anywhere, and it never sends telemetry.")
                bullet("The usage endpoints are unofficial. Vendors can change them without notice, "
                    + "so a provider may show as unavailable.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.shield")
            .font(.callout)
    }

    private func finish() {
        model.settings.hasCompletedOnboarding = true
        dismissWindow(id: WindowID.onboarding)
    }
}
