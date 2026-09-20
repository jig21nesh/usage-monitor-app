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
        Image(nsImage: MenuBarIconRenderer.image(for: status, colored: model.settings.colorsMenuBarIcon))
            .accessibilityLabel(MenuBarIconRenderer.accessibilityLabel(for: status))
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
