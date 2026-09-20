import Foundation

/// Pure mapping from `GetCurrentPeriodUsage` JSON to a snapshot. Money is in cents; the billing
/// cycle bounds are epoch milliseconds carried as strings. Lenient by design (ADR 0003).
public enum CursorUsageMapper {
    public static let includedWindowID = "cursor.included"
    public static let onDemandWindowID = "cursor.on-demand"

    public static func snapshot(
        from data: Data,
        credential: CursorCredential,
        now: Date
    ) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("cursor_json")
        }
        let start = cycleDate(payload.billingCycleStart)
        let end = cycleDate(payload.billingCycleEnd)
        var duration: TimeInterval?
        if let start, let end, end > start {
            duration = end.timeIntervalSince(start)
        }

        var windows: [UsageWindow] = []
        if let plan = payload.planUsage, let percent = try includedPercent(plan) {
            windows.append(UsageWindow(
                id: includedWindowID,
                title: "Included usage",
                kind: .monthly,
                usedPercent: percent,
                resetsAt: end,
                windowDuration: duration
            ))
        }
        if let spend = payload.spendLimitUsage, let percent = try onDemandPercent(spend) {
            windows.append(UsageWindow(
                id: onDemandWindowID,
                title: "On-demand usage",
                kind: .other,
                usedPercent: percent,
                resetsAt: end,
                windowDuration: duration
            ))
        }
        guard !windows.isEmpty else { throw .decoding("cursor_no_windows") }
        return UsageSnapshot(provider: .cursor, planName: credential.planName, windows: windows, fetchedAt: now)
    }

    /// Prefers the server's own percentage; otherwise spend over limit (or limit minus remaining,
    /// the only pair the live payload carries), skipping plans without a limit.
    static func includedPercent(_ plan: PlanUsage) throws(ProviderError) -> Double? {
        if let percent = plan.totalPercentUsed {
            guard percent.isFinite else { throw .decoding("cursor_percent") }
            return percent
        }
        guard let limit = plan.limit, limit.isFinite, limit > 0 else { return nil }
        let spend: Double
        if let known = plan.totalSpend ?? plan.includedSpend {
            spend = known
        } else if let remaining = plan.remaining {
            spend = limit - remaining
        } else {
            spend = 0
        }
        guard spend.isFinite else { throw .decoding("cursor_percent") }
        return spend / limit * 100
    }

    /// On-demand spend is metered against an individual cap first, else a pooled team cap.
    static func onDemandPercent(_ spend: SpendLimitUsage) throws(ProviderError) -> Double? {
        let pairs: [(Double?, Double?)] = [
            (spend.individualUsed, spend.individualLimit),
            (spend.pooledUsed, spend.pooledLimit),
        ]
        for (used, limit) in pairs {
            guard let limit, limit.isFinite, limit > 0 else { continue }
            let value = used ?? 0
            guard value.isFinite else { throw .decoding("cursor_percent") }
            return value / limit * 100
        }
        return nil
    }

    /// Cycle bounds arrive as epoch-millisecond strings; ISO 8601 and bare numbers are accepted too.
    static func cycleDate(_ raw: Cycle?) -> Date? {
        switch raw {
        case .number(let value):
            return VendorDates.epoch(value)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let number = Double(trimmed) { return VendorDates.epoch(number) }
            return VendorDates.iso8601(trimmed)
        case nil:
            return nil
        }
    }

    struct Payload: Decodable {
        let billingCycleStart: Cycle?
        let billingCycleEnd: Cycle?
        let planUsage: PlanUsage?
        let spendLimitUsage: SpendLimitUsage?
    }

    struct PlanUsage: Decodable {
        let totalSpend: Double?
        let includedSpend: Double?
        let bonusSpend: Double?
        let limit: Double?
        let remaining: Double?
        let totalPercentUsed: Double?
    }

    struct SpendLimitUsage: Decodable {
        let individualLimit: Double?
        let individualUsed: Double?
        let pooledLimit: Double?
        let pooledUsed: Double?
        let limitType: String?
    }

    enum Cycle: Decodable {
        case number(Double)
        case text(String)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else {
                self = .text(try container.decode(String.self))
            }
        }
    }
}
