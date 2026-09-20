import Foundation

/// Pure mapping from the Copilot user payload to a snapshot. Only the quota fields are decoded;
/// the payload also carries endpoints and feature flags that are ignored (ADR 0003).
public enum CopilotUsageMapper {
    static let premiumKey = "premium_interactions"
    static let secondaryKeys = ["chat", "completions"]

    public static func snapshot(
        from data: Data,
        login: String?,
        fetchedAt: Date
    ) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("copilot_json")
        }
        let snapshots = payload.quotaSnapshots ?? [:]
        let resetsAt = resetDate(payload: payload, snapshots: snapshots)
        var windows: [UsageWindow] = []
        if let premium = snapshots[premiumKey],
           let window = try window(premium, id: "copilot.premium", title: "Premium requests", resetsAt: resetsAt) {
            windows.append(window)
        }
        for key in secondaryKeys {
            guard let snapshot = snapshots[key], snapshot.unlimited == false else { continue }
            if let window = try window(snapshot, id: "copilot.\(key)", title: key.capitalized, resetsAt: resetsAt) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { throw .decoding("copilot_no_windows") }
        return UsageSnapshot(
            provider: .copilot,
            planName: planName(plan: payload.copilotPlan, sku: payload.accessTypeSku),
            windows: windows,
            fetchedAt: fetchedAt
        )
    }

    /// Nil when the snapshot is unlimited or carries nothing usable; throws only on corrupt numbers.
    static func window(
        _ snapshot: Snapshot,
        id: String,
        title: String,
        resetsAt: Date?
    ) throws(ProviderError) -> UsageWindow? {
        if snapshot.unlimited == true { return nil }
        let used: Double
        if let remaining = snapshot.percentRemaining {
            guard remaining.isFinite else { throw .decoding("copilot_percent") }
            used = 100 - remaining
        } else if let entitlement = snapshot.entitlement, let remaining = snapshot.remaining,
                  entitlement.isFinite, remaining.isFinite, entitlement > 0 {
            used = (entitlement - remaining) / entitlement * 100
        } else {
            return nil
        }
        return UsageWindow(
            id: id, title: title, kind: .monthly, usedPercent: used, resetsAt: resetsAt, windowDuration: nil
        )
    }

    /// `quota_reset_date_utc` is authoritative; the per-snapshot epoch is often 0, so it is a fallback only.
    static func resetDate(payload: Payload, snapshots: [String: Snapshot]) -> Date? {
        if let date = VendorDates.iso8601(payload.quotaResetDateUTC) { return date }
        if let date = midnightUTC(payload.quotaResetDate) { return date }
        let epochs = snapshots.values.compactMap { $0.quotaResetAt }.filter { $0 > 0 }
        return VendorDates.epoch(epochs.min())
    }

    /// GitHub also sends the reset as a bare `yyyy-MM-dd`, meaning midnight UTC on that day.
    static func midnightUTC(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), value.count == 10 else { return nil }
        return try? Date(value + "T00:00:00Z", strategy: .iso8601)
    }

    static func planName(plan: String?, sku: String?) -> String? {
        switch plan?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "free": return "Free"
        case "individual": return "Pro"
        case "individual_pro", "pro_plus": return "Pro+"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case let raw? where !raw.isEmpty: return raw.prefix(1).uppercased() + raw.dropFirst()
        default: break
        }
        let hint = sku?.lowercased() ?? ""
        if hint.contains("enterprise") { return "Enterprise" }
        if hint.contains("business") { return "Business" }
        if hint.contains("free") { return "Free" }
        return nil
    }

    struct Payload: Decodable {
        let login: String?
        let copilotPlan: String?
        let accessTypeSku: String?
        let quotaResetDate: String?
        let quotaResetDateUTC: String?
        let quotaSnapshots: [String: Snapshot]?

        enum CodingKeys: String, CodingKey {
            case login
            case copilotPlan = "copilot_plan"
            case accessTypeSku = "access_type_sku"
            case quotaResetDate = "quota_reset_date"
            case quotaResetDateUTC = "quota_reset_date_utc"
            case quotaSnapshots = "quota_snapshots"
        }
    }

    struct Snapshot: Decodable {
        let entitlement: Double?
        let remaining: Double?
        let percentRemaining: Double?
        let unlimited: Bool?
        let quotaResetAt: Double?

        enum CodingKeys: String, CodingKey {
            case entitlement
            case remaining
            case percentRemaining = "percent_remaining"
            case unlimited
            case quotaResetAt = "quota_reset_at"
        }
    }
}
