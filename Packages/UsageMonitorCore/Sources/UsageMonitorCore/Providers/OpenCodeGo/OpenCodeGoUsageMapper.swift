import Foundation

/// Pure mapping from the Go plan usage payload to a snapshot. The payload nests three windows
/// under `usage`: `rolling` (5 hours), `weekly` and `monthly`, each with a percent and a reset.
public enum OpenCodeGoUsageMapper {
    public static let planName = "Go"
    static let sessionDuration: TimeInterval = 18_000
    static let weekDuration: TimeInterval = 604_800

    public static func snapshot(from data: Data, fetchedAt: Date) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("opencode_json")
        }
        var windows: [UsageWindow] = []
        if let rolling = payload.usage?.rolling {
            windows.append(try window(
                rolling, id: "opencode.session", title: "Current session", kind: .session, duration: sessionDuration
            ))
        }
        if let weekly = payload.usage?.weekly {
            windows.append(try window(
                weekly, id: "opencode.weekly", title: "Weekly limit", kind: .weekly, duration: weekDuration
            ))
        }
        if let monthly = payload.usage?.monthly {
            windows.append(try window(
                monthly, id: "opencode.monthly", title: "Monthly limit", kind: .monthly, duration: nil
            ))
        }
        guard !windows.isEmpty else { throw .decoding("opencode_no_windows") }
        return UsageSnapshot(provider: .opencodeGo, planName: planName, windows: windows, fetchedAt: fetchedAt)
    }

    static func window(
        _ window: Window,
        id: String,
        title: String,
        kind: UsageWindowKind,
        duration: TimeInterval?
    ) throws(ProviderError) -> UsageWindow {
        guard let percent = window.percent, percent.isFinite else { throw .decoding("opencode_percent") }
        return UsageWindow(
            id: id,
            title: title,
            kind: kind,
            usedPercent: percent,
            resetsAt: window.resetsAt?.date,
            windowDuration: duration
        )
    }

    struct Payload: Decodable {
        let usage: Usage?
    }

    struct Usage: Decodable {
        let rolling: Window?
        let weekly: Window?
        let monthly: Window?
    }

    struct Window: Decodable {
        let status: String?
        let percent: Double?
        let resetsAt: Reset?
    }

    /// `resetsAt` has been seen as RFC 3339 text and as an epoch number; both are accepted.
    struct Reset: Decodable {
        let date: Date?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                date = VendorDates.epoch(number)
            } else if let text = try? container.decode(String.self) {
                date = VendorDates.iso8601(text) ?? VendorDates.epoch(Double(text))
            } else {
                date = nil
            }
        }
    }
}
