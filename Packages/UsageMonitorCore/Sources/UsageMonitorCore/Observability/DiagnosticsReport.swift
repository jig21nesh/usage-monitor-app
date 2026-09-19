import Foundation

/// Plain-text report for bug reports (ADR 0006). Everything passes through `Redactor` and the
/// account label is deliberately omitted because it may be an email address.
public enum DiagnosticsReport {
    /// What the report needs from the host: versions, the clock and the formatter to use.
    public struct Environment: Sendable {
        public var appVersion: String
        public var osVersion: String
        public var now: Date
        public var formatter: ResetFormatter

        public init(appVersion: String, osVersion: String, now: Date, formatter: ResetFormatter = ResetFormatter()) {
            self.appVersion = appVersion
            self.osVersion = osVersion
            self.now = now
            self.formatter = formatter
        }
    }

    public static func render(
        statuses: [ProviderStatus],
        diagnostics: [ProviderID: ProviderDiagnostics],
        settings: AppSettings,
        environment: Environment
    ) -> String {
        var lines: [String] = [
            "AI Usage Monitor diagnostics",
            "generated: \(iso(environment.now))",
            "app_version: \(environment.appVersion)",
            "os_version: \(environment.osVersion)",
            "refresh_interval: \(settings.refreshInterval.title)",
            "enabled_providers: \(list(settings.enabledProviders.map(\.rawValue)))",
            "launch_at_login: \(settings.launchAtLogin)",
            "percent_style: \(settings.percentStyle.rawValue)",
        ]
        for status in statuses {
            lines.append("")
            let section = section(for: status, diagnostic: diagnostics[status.provider], environment: environment)
            lines.append(contentsOf: section)
        }
        return Redactor.redact(lines.joined(separator: "\n") + "\n")
    }

    private static func section(
        for status: ProviderStatus,
        diagnostic: ProviderDiagnostics?,
        environment: Environment
    ) -> [String] {
        let formatter = environment.formatter
        var lines = [
            "[\(status.provider.rawValue)]",
            "enabled: \(status.isEnabled)",
            "link: \(linkText(status.link))",
            "plan: \(status.snapshot?.planName ?? status.link.account?.planName ?? "unknown")",
        ]
        for window in status.snapshot?.windows ?? [] {
            let reset = formatter.resetText(for: window.resetsAt, now: environment.now)
            lines.append("window: \(window.title) \(formatter.usedText(window)) \(reset)")
        }
        lines.append("last_success: \(status.lastSuccess.map(iso) ?? "none")")
        lines.append("last_error: \(status.lastError?.logIdentifier ?? "none")")
        lines.append("next_retry: \(status.nextRetryAt.map(iso) ?? "none")")
        lines.append("stale: \(status.isStale)")
        let counters = diagnostic ?? ProviderDiagnostics()
        lines.append("polls: \(counters.polls) successes: \(counters.successes) failures: \(counters.failures)")
        lines.append("last_duration_ms: \(counters.lastDuration.map { String($0.milliseconds) } ?? "none")")
        return lines
    }

    private static func linkText(_ link: LinkState) -> String {
        switch link {
        case .unknown: "unknown"
        case .linked(let account): "linked via \(account.origin)"
        case .notLinked(let error): "not linked (\(error.logIdentifier))"
        }
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func list(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.sorted().joined(separator: ", ")
    }
}
