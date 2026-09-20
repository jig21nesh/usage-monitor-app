import AppKit
import UsageMonitorCore

/// Builds the status item image: a gauge whose needle follows the tracked window and whose
/// colour follows the threshold level (ADR 0008). Pure functions so the mapping is testable.
enum MenuBarIconRenderer {
    enum NeedleBucket: String, CaseIterable {
        case empty = "gauge.with.dots.needle.0percent"
        case third = "gauge.with.dots.needle.33percent"
        case twoThirds = "gauge.with.dots.needle.67percent"
        case full = "gauge.with.dots.needle.100percent"
    }

    static let pointSize: CGFloat = 14

    /// Nil percent (unknown) shows an empty gauge.
    static func bucket(forPercent percent: Double?) -> NeedleBucket {
        guard let percent, percent.isFinite else { return .empty }
        switch percent {
        case ..<25: return .empty
        case ..<50: return .third
        case ..<75: return .twoThirds
        default: return .full
        }
    }

    /// Stale numbers are shown grey even when the last known level was green: the colour is a
    /// live signal, not a memory.
    static func tint(for level: MenuBarLevel, isStale: Bool) -> NSColor {
        guard !isStale else { return .secondaryLabelColor }
        switch level {
        case .ok: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }

    static func image(level: MenuBarLevel, bucket: NeedleBucket, isStale: Bool, colored: Bool) -> NSImage {
        let base = NSImage(systemSymbolName: bucket.rawValue, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: nil)
            ?? NSImage()
        var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        if colored {
            configuration = configuration.applying(
                NSImage.SymbolConfiguration(hierarchicalColor: tint(for: level, isStale: isStale))
            )
        }
        let image = base.withSymbolConfiguration(configuration) ?? base
        // A template image is recoloured by the system; only the monochrome option wants that.
        image.isTemplate = !colored
        return image
    }

    static func image(for status: MenuBarStatus, colored: Bool) -> NSImage {
        image(
            level: status.level,
            bucket: bucket(forPercent: status.window?.usedPercent),
            isStale: status.isStale,
            colored: colored
        )
    }

    /// "OpenAI session 42% used"; providers without a session window name the tracked window instead.
    static func accessibilityLabel(for status: MenuBarStatus) -> String {
        guard let provider = status.provider, let window = status.window else { return "Usage unknown" }
        let percent = Int(window.usedPercent.rounded())
        let staleSuffix = status.isStale ? ", stale" : ""
        let subject = window.kind == .session ? "session" : window.title.lowercased()
        return "\(provider.displayName) \(subject) \(percent)% used\(staleSuffix)"
    }
}
