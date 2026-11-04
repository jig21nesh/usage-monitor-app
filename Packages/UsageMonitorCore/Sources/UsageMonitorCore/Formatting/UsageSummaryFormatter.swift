import Foundation

public enum UsageSummaryFormatter {
    public static func menuBarPercentage(for status: MenuBarStatus, style: PercentStyle) -> String {
        guard let window = status.window else { return "—" }
        let percent = style == .used ? window.usedPercent : window.remainingPercent
        return "\(Int(percent.rounded()))%\(status.isStale ? "*" : "")"
    }

    public static func menuBarSummary(
        for status: MenuBarStatus,
        style: PercentStyle,
        now: Date,
        formatter: ResetFormatter = ResetFormatter()
    ) -> String {
        guard let provider = status.provider, let window = status.window else { return "Usage unknown" }
        let subject = window.kind == .session ? "session" : window.title.lowercased()
        var lines = ["\(provider.displayName) \(subject) \(formatter.percentText(window, style: style))"]
        if status.isStale { lines.append("Stale — last known usage; refresh to check current limits.") }
        lines.append(formatter.resetCountdown(for: window.resetsAt, now: now))
        if let exact = formatter.resetDateText(for: window.resetsAt) { lines.append(exact) }
        return lines.joined(separator: "\n")
    }

    public static func availableResets(_ count: Int?, isStale: Bool) -> String {
        guard let count, count >= 0 else { return "Available resets: not reported" }
        let text = "\(count) \(count == 1 ? "reset" : "resets") available"
        return isStale ? "\(text) (last known)" : text
    }
}
