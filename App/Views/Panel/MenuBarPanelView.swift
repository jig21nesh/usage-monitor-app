import SwiftUI
import UsageMonitorCore

/// Content of the menu bar extra window (and of the debug "Panel Preview" window).
struct MenuBarPanelView: View {
    @Environment(UsageMonitorModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if model.visibleStatuses.isEmpty {
                    ContentUnavailableView(
                        "No providers enabled",
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text("Choose providers in Settings.")
                    )
                    .accessibilityIdentifier("panel.empty")
                }
                ForEach(model.visibleStatuses) { status in
                    ProviderSectionView(status: status)
                }
            }
            .padding(16)
            Divider()
            PanelFooterView()
        }
        .frame(width: 400)
    }
}

#if DEBUG
#Preview("Linked") {
    MenuBarPanelView()
        .environment(PreviewComposition.makeModel(options: LaunchOptions(isUITesting: true)))
}
#endif
