import SwiftUI
import UsageMonitorCore

/// A usage bar with both a ticking countdown and the exact reset date in the user's time zone.
struct UsageWindowRow: View {
    @Environment(UsageMonitorModel.self) private var model
    let window: UsageWindow

    private var percentText: String {
        UsageText.percent(window, style: model.settings.percentStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 12) {
                Text(window.title)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                    .accessibilityIdentifier("panel.window.\(window.id).title")
                ProgressView(value: window.usedPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(Self.tint(forPercent: window.usedPercent))
                    .accessibilityLabel(window.title)
                    .accessibilityValue(percentText)
                Text(percentText)
                    .font(.callout.monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
                    .accessibilityIdentifier("panel.window.\(window.id).percent")
            }
            TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { context in
                HStack(alignment: .top, spacing: 8) {
                    Text(ResetText.formatter.resetCountdown(for: window.resetsAt, now: context.date))
                        .accessibilityIdentifier("panel.window.\(window.id).reset")
                    Spacer(minLength: 0)
                    if let exact = ResetText.formatter.resetDateText(for: window.resetsAt) {
                        Text(exact)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("panel.window.\(window.id).resetDate")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
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
