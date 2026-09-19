import Foundation

/// Pure mapping from the usage payload to a snapshot. Lenient by design: the payload carries many
/// undocumented keys and fields have been renamed before (ADR 0003).
public enum ClaudeUsageMapper {
    static let sessionDuration: TimeInterval = 18_000
    static let weekDuration: TimeInterval = 604_800

    public static func snapshot(
        from data: Data,
        planName: String?,
        fetchedAt: Date
    ) throws(ProviderError) -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: data)
        } catch {
            throw .decoding("claude_json")
        }
        var windows = try windows(fromLimits: payload.limits ?? [])
        if windows.isEmpty {
            windows = try legacyWindows(from: payload)
        }
        guard !windows.isEmpty else { throw .decoding("claude_no_windows") }
        return UsageSnapshot(provider: .claude, planName: planName, windows: windows, fetchedAt: fetchedAt)
    }

    /// The `limits[]` array is the newer shape and the only one that carries per-model rows.
    static func windows(fromLimits limits: [Limit]) throws(ProviderError) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for limit in limits {
            if let window = try window(from: limit) {
                windows.append(window)
            }
        }
        return windows
    }

    static func window(from limit: Limit) throws(ProviderError) -> UsageWindow? {
        let resetsAt = VendorDates.iso8601(limit.resetsAt)
        switch limit.kind {
        case "session":
            return UsageWindow(
                id: "claude.session", title: "Current session", kind: .session,
                usedPercent: try percent(limit.percent), resetsAt: resetsAt, windowDuration: sessionDuration
            )
        case "weekly_all":
            return UsageWindow(
                id: "claude.weekly.all", title: "All models", kind: .weekly,
                usedPercent: try percent(limit.percent), resetsAt: resetsAt, windowDuration: weekDuration
            )
        case "weekly_scoped":
            let name = limit.scope?.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Model"
            return UsageWindow(
                id: "claude.weekly.\(slug(title))", title: title, kind: .weeklyModel,
                usedPercent: try percent(limit.percent), resetsAt: resetsAt, windowDuration: weekDuration
            )
        default:
            // Unknown kinds are skipped rather than fatal so a new vendor row never blanks the panel.
            return nil
        }
    }

    /// Older payloads (and some accounts today) only fill the top-level buckets.
    static func legacyWindows(from payload: Payload) throws(ProviderError) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        if let bucket = payload.fiveHour {
            windows.append(try legacyWindow(
                bucket, id: "claude.session", title: "Current session", kind: .session, duration: sessionDuration
            ))
        }
        if let bucket = payload.sevenDay {
            windows.append(try legacyWindow(
                bucket, id: "claude.weekly.all", title: "All models", kind: .weekly, duration: weekDuration
            ))
        }
        if let bucket = payload.sevenDayOpus {
            windows.append(try legacyWindow(
                bucket, id: "claude.weekly.opus", title: "Opus", kind: .weeklyModel, duration: weekDuration
            ))
        }
        if let bucket = payload.sevenDaySonnet {
            windows.append(try legacyWindow(
                bucket, id: "claude.weekly.sonnet", title: "Sonnet", kind: .weeklyModel, duration: weekDuration
            ))
        }
        return windows
    }

    static func legacyWindow(
        _ bucket: Bucket,
        id: String,
        title: String,
        kind: UsageWindowKind,
        duration: TimeInterval
    ) throws(ProviderError) -> UsageWindow {
        UsageWindow(
            id: id, title: title, kind: kind,
            usedPercent: try percent(bucket.utilization),
            resetsAt: VendorDates.iso8601(bucket.resetsAt),
            windowDuration: duration
        )
    }

    static func percent(_ value: Double?) throws(ProviderError) -> Double {
        guard let value, value.isFinite else { throw .decoding("claude_percent") }
        return value
    }

    /// Stable identifier fragment from a display name, e.g. "Claude Opus 4.1" -> "claude-opus-4-1".
    static func slug(_ text: String) -> String {
        var result = ""
        var previousWasDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "model" : trimmed
    }

    struct Payload: Decodable {
        let fiveHour: Bucket?
        let sevenDay: Bucket?
        let sevenDayOpus: Bucket?
        let sevenDaySonnet: Bucket?
        let limits: [Limit]?
    }

    struct Bucket: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
    }

    struct Scope: Decodable {
        let model: Model?
    }

    struct Model: Decodable {
        let displayName: String?
    }
}
