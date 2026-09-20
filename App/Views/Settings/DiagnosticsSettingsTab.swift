import AppKit
import SwiftUI
import UsageMonitorCore

/// Read-only view of the local counters (ADR 0006). Nothing here ever contains a credential.
struct DiagnosticsSettingsTab: View {
    @Environment(UsageMonitorModel.self) private var model
    @State private var copiedAt: Date?

    private struct Row: Identifiable {
        let id: ProviderID
        let diagnostics: ProviderDiagnostics
        let status: ProviderStatus?
    }

    /// One row per registered provider, so test builds with three providers show three rows.
    private var rows: [Row] {
        model.statuses.map { status in
            Row(
                id: status.provider,
                diagnostics: model.diagnostics[status.provider] ?? ProviderDiagnostics(),
                status: status
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(rows) {
                TableColumn("Provider") { Text($0.id.displayName) }
                TableColumn("Polls") { Text("\($0.diagnostics.polls)") }
                TableColumn("OK") { Text("\($0.diagnostics.successes)") }
                TableColumn("Failed") { Text("\($0.diagnostics.failures)") }
                TableColumn("Last ms") { Text($0.diagnostics.lastDuration.map { "\($0.milliseconds)" } ?? "–") }
                TableColumn("Last error") { Text($0.diagnostics.lastErrorIdentifier ?? "–") }
                TableColumn("Last success") { row in
                    Text(row.diagnostics.lastSuccessAt.map { $0.formatted(.dateTime.hour().minute().second()) } ?? "–")
                }
            }
            .accessibilityIdentifier("settings.diagnostics.table")
            VStack(alignment: .leading, spacing: 4) {
                Text("App \(Self.appVersion) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                Text("Enabled: \(enabledList) · Refresh every \(model.settings.refreshInterval.title)")
                Text("Logs: Console.app, subsystem \(UsageLog.subsystem). Tokens are never logged.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.diagnostics.footer")
            HStack {
                Spacer()
                if copiedAt != nil {
                    Text("Copied").font(.caption).foregroundStyle(.secondary)
                }
                Button("Copy report") {
                    copyReport()
                }
                .accessibilityIdentifier("settings.diagnostics.copy")
            }
        }
        .padding()
    }

    /// The report is redacted in Core before it reaches the pasteboard (ADR 0006).
    private func copyReport() {
        let report = model.diagnosticsReport(
            appVersion: Self.appVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        copiedAt = .now
    }

    private var enabledList: String {
        let names = model.visibleStatuses.map(\.provider.displayName)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
