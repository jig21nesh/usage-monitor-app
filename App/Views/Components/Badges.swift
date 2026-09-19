import SwiftUI
import UsageMonitorCore

struct PlanBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Plan \(text)")
    }
}

struct ExperimentalTag: View {
    var body: some View {
        Text("Experimental")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
            .accessibilityLabel("Experimental provider")
    }
}

/// Trailing header indicator: spinner while refreshing, "Stale" when the last poll failed.
struct ProviderStatusIndicator: View {
    let status: ProviderStatus

    var body: some View {
        if status.isRefreshing {
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Refreshing")
        } else if status.isStale {
            Label("Stale", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if status.lastError != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Error")
        }
    }
}

struct LinkStateLabel: View {
    let link: LinkState

    var body: some View {
        switch link {
        case .unknown:
            Label("Checking…", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        case .linked:
            Label("Linked", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notLinked(let error):
            Label(error.requiresRelink ? "Not linked" : "Unavailable", systemImage: "xmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}
