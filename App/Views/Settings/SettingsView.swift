import SwiftUI
import UsageMonitorCore

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountsSettingsTab()
            }
            Tab("Providers", systemImage: "list.bullet") {
                ProvidersSettingsTab()
            }
            Tab("Refresh", systemImage: "clock.arrow.2.circlepath") {
                RefreshSettingsTab()
            }
            Tab("Diagnostics", systemImage: "stethoscope") {
                DiagnosticsSettingsTab()
            }
        }
        .frame(width: 580, height: 500)
    }
}
