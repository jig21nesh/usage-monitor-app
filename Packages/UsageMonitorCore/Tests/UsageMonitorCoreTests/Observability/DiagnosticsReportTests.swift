import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("DiagnosticsReport")
struct DiagnosticsReportTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let formatter = ResetFormatter(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC")!,
        locale: Locale(identifier: "en_US")
    )

    private func render(_ statuses: [ProviderStatus], diagnostics: [ProviderID: ProviderDiagnostics] = [:]) -> String {
        var settings = AppSettings.default
        settings.enabledProviders = [.grok, .claude]
        return DiagnosticsReport.render(
            statuses: statuses,
            diagnostics: diagnostics,
            settings: settings,
            environment: .init(appVersion: "0.1.0", osVersion: "macOS 27.0", now: now, formatter: formatter)
        )
    }

    @Test func describesSettingsAndEveryProvider() {
        let window = UsageWindow(
            id: "claude.session",
            title: "Current session",
            kind: .session,
            usedPercent: 21,
            resetsAt: now.addingTimeInterval(3600 + 5 * 60)
        )
        let snapshot = UsageSnapshot(provider: .claude, planName: "Max", windows: [window], fetchedAt: now)
        var status = ProviderStatus(provider: .claude, isEnabled: true)
        status.link = .linked(AccountInfo(planName: "Max", accountLabel: nil, origin: "Claude Code"))
        status.snapshot = snapshot
        status.lastSuccess = now
        status.lastError = .serverError(status: 503)
        status.nextRetryAt = now.addingTimeInterval(180)
        var counters = ProviderDiagnostics()
        counters.polls = 3
        counters.successes = 2
        counters.failures = 1
        counters.lastDuration = .milliseconds(350)

        let report = render([status], diagnostics: [.claude: counters])

        let expectedLines = [
            "AI Usage Monitor diagnostics",
            "generated: 2027-01-15T08:00:00Z",
            "app_version: 0.1.0",
            "os_version: macOS 27.0",
            "refresh_interval: 2 minutes",
            "enabled_providers: claude, grok",
            "launch_at_login: false",
            "percent_style: used",
            "[claude]",
            "enabled: true",
            "link: linked via Claude Code",
            "plan: Max",
            "window: Current session 21% used Resets in 1 hr 5 min",
            "last_success: 2027-01-15T08:00:00Z",
            "last_error: server_error:503",
            "next_retry: 2027-01-15T08:03:00Z",
            "stale: true",
            "polls: 3 successes: 2 failures: 1",
            "last_duration_ms: 350",
        ]
        for line in expectedLines {
            #expect(report.contains(line + "\n"), "missing line: \(line)")
        }
        #expect(report.hasSuffix("\n"))
    }

    @Test func neverLeaksCredentialShapedTextOrAccountLabels() {
        var status = ProviderStatus(provider: .openAI, isEnabled: true)
        status.link = .linked(AccountInfo(planName: "Pro", accountLabel: "me@example.com", origin: "Codex CLI"))
        status.lastError = .credentialsUnreadable("sk-ant-oat01-SECRETTOKEN123456")
        let report = render([status])

        #expect(!report.contains("SECRETTOKEN"))
        #expect(!report.contains("me@example.com"))
        #expect(report.contains(Redactor.mask))
        #expect(report.contains("plan: Pro"))
    }

    @Test func describesUnlinkedAndUnknownProvidersWithoutCounters() {
        var unlinked = ProviderStatus(provider: .grok, isEnabled: false)
        unlinked.link = .notLinked(.credentialsNotFound)
        let unknown = ProviderStatus(provider: .claude, isEnabled: true)
        let report = render([unlinked, unknown])

        #expect(report.contains("[grok]\nenabled: false\nlink: not linked (credentials_not_found)\nplan: unknown\n"))
        #expect(report.contains("[claude]\nenabled: true\nlink: unknown\n"))
        #expect(report.contains("last_success: none\nlast_error: none\nnext_retry: none\nstale: false\n"))
        #expect(report.contains("polls: 0 successes: 0 failures: 0\nlast_duration_ms: none\n"))
    }

    @Test func emptyStateStillProducesTheHeader() {
        var settings = AppSettings.default
        settings.enabledProviders = []
        let report = DiagnosticsReport.render(
            statuses: [],
            diagnostics: [:],
            settings: settings,
            environment: .init(appVersion: "0.0.0", osVersion: "macOS 26.0", now: now, formatter: formatter)
        )
        #expect(report.contains("enabled_providers: none\n"))
        #expect(!report.contains("["))
        #expect(report.hasSuffix("percent_style: used\n"))
    }
}
