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
        MenuBarStatusView(status: status, settings: model.settings)
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

    private var status: MenuBarStatus { model.menuBarStatus }
}

/// Shared by the real status item and Settings so the preview includes the same percentage.
struct MenuBarStatusView: View {
    let status: MenuBarStatus
    let settings: AppSettings

    var body: some View {
        // MenuBarExtra bridges its label to an NSStatusBarButton. A TimelineView here repeatedly
        // invalidates that bridge on macOS 27; keep the label static between usage/settings updates.
        let summary = UsageSummaryFormatter.menuBarSummary(for: status, style: settings.percentStyle, now: .now)
        label
            .help(summary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
    }

    @ViewBuilder
    private var label: some View {
        if settings.showsMenuBarPercentage {
            Label {
                Text(UsageSummaryFormatter.menuBarPercentage(for: status, style: settings.percentStyle))
                    .monospacedDigit()
                    .accessibilityIdentifier("menubar.percentage")
            } icon: {
                Image(nsImage: MenuBarIconRenderer.image(for: status, colored: settings.colorsMenuBarIcon))
            }
            .labelStyle(.titleAndIcon)
        } else {
            Image(nsImage: MenuBarIconRenderer.image(for: status, colored: settings.colorsMenuBarIcon))
        }
    }
}
