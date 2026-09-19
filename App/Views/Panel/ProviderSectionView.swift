import SwiftUI
import UsageMonitorCore

/// One provider block in the panel: header, then usage rows or the not-linked / waiting state.
struct ProviderSectionView: View {
    let status: ProviderStatus

    private var id: String { status.provider.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot = status.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window)
                }
                if let error = status.lastError {
                    Label(error.userMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("panel.provider.\(id).error")
                }
            } else {
                ProviderPlaceholderView(status: status)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel.provider.\(id)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: status.provider.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(status.provider.displayName)
                .font(.headline)
                .accessibilityIdentifier("panel.provider.\(id).name")
            if let plan = status.snapshot?.planName ?? status.link.account?.planName {
                PlanBadge(text: plan)
                    .accessibilityIdentifier("panel.provider.\(id).plan")
            }
            if status.provider.isExperimental {
                ExperimentalTag()
            }
            Spacer()
            ProviderStatusIndicator(status: status)
                .accessibilityIdentifier("panel.provider.\(id).status")
        }
    }
}

/// Shown instead of usage rows while a provider has no snapshot yet.
struct ProviderPlaceholderView: View {
    @Environment(UsageMonitorModel.self) private var model
    let status: ProviderStatus
    @State private var isRelinking = false

    private var id: String { status.provider.rawValue }

    var body: some View {
        switch status.link {
        case .unknown:
            Label("Checking for a stored login…", systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .linked:
            Text(status.lastError?.userMessage ?? "Waiting for the first refresh…")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .notLinked(let error):
            notLinked(error)
        }
    }

    private func notLinked(_ error: ProviderError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.userMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("panel.provider.\(id).message")
            HStack(spacing: 10) {
                CopyableCommand(
                    command: status.provider.loginCommand,
                    identifier: "panel.provider.\(id).loginCommand"
                )
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
                .accessibilityIdentifier("panel.provider.\(id).relink")
            }
        }
    }
}
