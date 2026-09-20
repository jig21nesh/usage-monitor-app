import Foundation

/// Pure mapping from the key endpoint's payload to a snapshot. The payload also carries the
/// account's API key; `Payload` deliberately has no property for it, so the key is never decoded,
/// never held and never logged (ADR 0003 amendment).
public enum MuseUsageMapper {
    public static let sessionID = "muse.session"
    public static let weeklyID = "muse.weekly"
    public static let payAsYouGoPlan = "Pay as you go"

    static let defaultSessionDuration: TimeInterval = 18_000
    static let weekDuration: TimeInterval = 604_800
    /// `resets_at` outside this range is garbage or unknown units, not a date worth showing.
    static let earliestReset = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
    static let latestReset = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01

    struct Payload: Decodable {
        let isSubsActive: Bool?
        let subsTierName: String?
        let subsUsage: Usage?

        enum CodingKeys: String, CodingKey {
            case isSubsActive = "is_subs_active"
            case subsTierName = "subs_tier_name"
            case subsUsage = "subs_usage"
        }
    }

    struct Usage: Decodable {
        let window: Window?
        let weekly: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Double?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowDurationMins = "window_duration_mins"
            case resetsAt = "resets_at"
        }
    }

    public static func snapshot(from data: Data, fetchedAt: Date) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try makeDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("muse_json")
        }
        if payload.isSubsActive == false {
            return UsageSnapshot(provider: .muse, planName: payAsYouGoPlan, windows: [], fetchedAt: fetchedAt)
        }
        let plan = planName(from: payload.subsTierName)
        guard let usage = payload.subsUsage else {
            // Seen on active plans: the tier is known but the meters are missing. Not an error.
            UsageLog.providers.debug("muse subscription active but no usage meters in response")
            return UsageSnapshot(provider: .muse, planName: plan, windows: [], fetchedAt: fetchedAt)
        }
        var windows: [UsageWindow] = []
        if let window = usage.window, let percent = try percent(window.usedPercent) {
            windows.append(UsageWindow(
                id: sessionID,
                title: "Current session",
                kind: .session,
                usedPercent: percent,
                resetsAt: resetDate(window.resetsAt),
                windowDuration: sessionDuration(minutes: window.windowDurationMins)
            ))
        }
        if let weekly = usage.weekly, let percent = try percent(weekly.usedPercent) {
            windows.append(UsageWindow(
                id: weeklyID,
                title: "Weekly limit",
                kind: .weekly,
                usedPercent: percent,
                resetsAt: resetDate(weekly.resetsAt),
                windowDuration: weekDuration
            ))
        }
        return UsageSnapshot(provider: .muse, planName: plan, windows: windows, fetchedAt: fetchedAt)
    }

    static func planName(from tier: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty else { return nil }
        return tier
    }

    /// Absent is fine (the window is skipped); present but not a number is a vendor change worth surfacing.
    static func percent(_ value: Double?) throws(ProviderError) -> Double? {
        guard let value else { return nil }
        guard value.isFinite else { throw .decoding("muse_percent") }
        return value
    }

    static func sessionDuration(minutes: Double?) -> TimeInterval {
        guard let minutes, minutes.isFinite, minutes > 0 else { return defaultSessionDuration }
        return minutes * 60
    }

    static func resetDate(_ raw: Double?) -> Date? {
        guard let date = VendorDates.epoch(raw), date >= earliestReset, date <= latestReset else { return nil }
        return date
    }

    /// Accepting the textual non-finite spellings lets `percent` reject them explicitly instead of
    /// surfacing a generic decode failure.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
