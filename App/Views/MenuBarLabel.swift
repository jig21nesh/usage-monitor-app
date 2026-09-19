import SwiftUI
import UsageMonitorCore

/// The status item itself. It is the one view that exists from launch, so it also performs the
/// startup routing (onboarding, debug windows) once.
struct MenuBarLabel: View {
    @Environment(UsageMonitorModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var didRoute = false

    var body: some View {
        Label("AI Usage Monitor", systemImage: symbolName)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("menubar.extra")
            .task {
                guard !didRoute else { return }
                didRoute = true
                await StartupRouter.route(
                    AppComposition.launchOptions,
                    model: model,
                    openWindow: openWindow,
                    openSettings: openSettings
                )
            }
    }

    /// The gauge fills with the most-used window across visible providers.
    private var symbolName: String {
        let peak = model.visibleStatuses
            .compactMap { $0.snapshot?.mostUsedWindow?.usedPercent }
            .max() ?? 0
        return Self.gaugeSymbol(forPercent: peak)
    }

    static func gaugeSymbol(forPercent percent: Double) -> String {
        switch percent {
        case ..<17: "gauge.with.dots.needle.0percent"
        case ..<42: "gauge.with.dots.needle.33percent"
        case ..<59: "gauge.with.dots.needle.50percent"
        case ..<84: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }
}
