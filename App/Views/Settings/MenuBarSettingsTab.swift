import SwiftUI
import UsageMonitorCore

/// Which provider drives the menu bar icon and where the colours change (ADR 0008).
struct MenuBarSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Status") {
                Picker("Status follows", selection: $model.settings.menuBarProvider) {
                    Text("Automatic").tag(ProviderID?.none)
                    ForEach(model.visibleStatuses) { status in
                        Text(status.provider.displayName).tag(Optional(status.provider))
                    }
                }
                .accessibilityIdentifier("settings.menubar.provider")
                Text(Self.automaticHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.menubar.help")
            }
            Section("Colours") {
                Toggle("Colour the menu bar icon", isOn: $model.settings.colorsMenuBarIcon)
                    .accessibilityIdentifier("settings.menubar.color")
                Stepper(value: warningBinding, in: 0...100, step: 5) {
                    LabeledContent("Orange from", value: Self.percentText(thresholds.warningPercent))
                }
                .accessibilityIdentifier("settings.menubar.warning")
                Stepper(value: criticalBinding, in: 0...100, step: 5) {
                    LabeledContent("Red from", value: Self.percentText(thresholds.criticalPercent))
                }
                .accessibilityIdentifier("settings.menubar.critical")
                Text("Green below the orange threshold. Grey while a provider is unknown or stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Preview") {
                MenuBarPreviewRow(status: model.menuBarStatus, colored: model.settings.colorsMenuBarIcon)
            }
        }
        .formStyle(.grouped)
    }

    static let automaticHelp = "Automatic follows the only enabled provider, or, with several enabled, "
        + "the one whose session limit is fullest."

    private var thresholds: MenuBarThresholds { model.settings.menuBarThresholds }

    static func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Both steppers rebuild `MenuBarThresholds` so Core keeps the pair clamped and ordered.
    private var warningBinding: Binding<Double> {
        Binding(
            get: { model.settings.menuBarThresholds.warningPercent },
            set: { newValue in
                let current = model.settings.menuBarThresholds
                model.settings.menuBarThresholds = MenuBarThresholds(
                    warningPercent: newValue,
                    criticalPercent: max(current.criticalPercent, newValue)
                )
            }
        )
    }

    private var criticalBinding: Binding<Double> {
        Binding(
            get: { model.settings.menuBarThresholds.criticalPercent },
            set: { newValue in
                let current = model.settings.menuBarThresholds
                model.settings.menuBarThresholds = MenuBarThresholds(
                    warningPercent: min(current.warningPercent, newValue),
                    criticalPercent: newValue
                )
            }
        )
    }
}

/// The three colour states side by side, plus what the icon is tracking right now.
struct MenuBarPreviewRow: View {
    let status: MenuBarStatus
    let colored: Bool

    struct Sample: Identifiable {
        let title: String
        let level: MenuBarLevel
        let bucket: MenuBarIconRenderer.NeedleBucket

        var id: String { title }
    }

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Self.samples) { sample in
                VStack(spacing: 4) {
                    Image(nsImage: MenuBarIconRenderer.image(
                        level: sample.level, bucket: sample.bucket, isStale: false, colored: colored
                    ))
                    Text(sample.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(sample.title) icon")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Image(nsImage: MenuBarIconRenderer.image(for: status, colored: colored))
                Text(MenuBarIconRenderer.accessibilityLabel(for: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.menubar.tracking")
            }
        }
        .padding(.vertical, 4)
    }

    private static let samples: [Sample] = [
        Sample(title: "Green", level: .ok, bucket: .third),
        Sample(title: "Orange", level: .warning, bucket: .twoThirds),
        Sample(title: "Red", level: .critical, bucket: .full),
    ]
}
