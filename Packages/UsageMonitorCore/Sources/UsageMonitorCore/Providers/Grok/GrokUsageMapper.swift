import Foundation

/// Pure mapping from the billing payload to a snapshot. The payload is proto3 JSON, so any
/// zero-valued scalar is simply absent.
public enum GrokUsageMapper {
    struct Payload: Decodable {
        let config: Config?
        let subscriptionTier: String?
    }

    struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
    }

    struct Period: Decodable {
        let start: String?
        let end: String?
    }

    public static let windowID = "grok.weekly"
    public static let windowTitle = "Weekly usage"

    public static func snapshot(from data: Data, fetchedAt: Date) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try makeDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("grok_json")
        }
        guard let config = payload.config else {
            throw .decoding("grok_no_config")
        }
        let percent = config.creditUsagePercent ?? 0
        guard percent.isFinite else {
            throw .decoding("grok_percent")
        }
        let start = VendorDates.iso8601(config.currentPeriod?.start)
        let end = VendorDates.iso8601(config.currentPeriod?.end)
        var duration: TimeInterval?
        if let start, let end, end > start {
            duration = end.timeIntervalSince(start)
        }
        let window = UsageWindow(
            id: windowID,
            title: windowTitle,
            kind: .weekly,
            usedPercent: percent,
            resetsAt: end,
            windowDuration: duration
        )
        return UsageSnapshot(
            provider: .grok,
            planName: planName(from: payload.subscriptionTier),
            windows: [window],
            fetchedAt: fetchedAt
        )
    }

    static func planName(from tier: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespaces), !tier.isEmpty else { return nil }
        let normalized = tier.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "supergrok": return "SuperGrok"
        case "supergrokheavy": return "SuperGrok Heavy"
        case "premiumplus": return "Premium+"
        case "premium": return "Premium"
        case "free": return nil
        default: return tier
        }
    }

    /// Accepting the textual non-finite spellings lets the guard above reject them explicitly
    /// instead of surfacing a generic decode failure.
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
