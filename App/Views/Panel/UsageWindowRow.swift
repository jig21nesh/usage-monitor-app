import SwiftUI
import UsageMonitorCore

/// Title and reset subtitle on the left, bar in the middle, "N% used" on the right.
struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                    .font(.callout)
                    .lineLimit(1)
                    .accessibilityIdentifier("panel.window.\(window.id).title")
                Text(ResetText.text(for: window.resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("panel.window.\(window.id).reset")
            }
            .frame(width: 140, alignment: .leading)
            ProgressView(value: window.usedPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(Self.tint(forPercent: window.usedPercent))
                .accessibilityLabel(window.title)
                .accessibilityValue(UsageText.used(window.usedPercent))
            Text(UsageText.used(window.usedPercent))
                .font(.callout.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
                .accessibilityIdentifier("panel.window.\(window.id).percent")
        }
    }

    static func tint(forPercent percent: Double) -> Color {
        switch percent {
        case ..<70: .accentColor
        case ..<90: .orange
        default: .red
        }
    }
}
