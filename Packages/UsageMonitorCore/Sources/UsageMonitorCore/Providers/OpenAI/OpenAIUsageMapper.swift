import Foundation

/// Pure mapping from the `wham/usage` JSON to a snapshot. Windows are classified by their
/// length, never by their position: Plus accounts have been seen with only the weekly window
/// sitting in `primary_window` (ADR 0003).
public enum OpenAIUsageMapper {
    static let sessionSeconds = 18_000.0
    static let weeklySeconds = 604_800.0

    public static func snapshot(
        from data: Data,
        credential: OpenAICredential,
        now: Date
    ) throws(ProviderError) -> UsageSnapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .decoding("openai_json")
        }

        var windows = try accountWindows(payload.rateLimit, now: now)
        for limit in payload.additionalRateLimits ?? [] {
            windows += try additionalWindows(limit, now: now)
        }
        guard !windows.isEmpty else { throw .decoding("openai_no_windows") }

        return UsageSnapshot(
            provider: .openAI,
            planName: OpenAIPlan.displayName(payload.planType ?? credential.planType),
            windows: windows,
            fetchedAt: now
        )
    }

    private static func accountWindows(_ rateLimit: RateLimit?, now: Date) throws(ProviderError) -> [UsageWindow] {
        guard let rateLimit else { return [] }
        var classified: [(WindowClass, UsageWindow)] = []
        for raw in [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap({ $0 }) {
            let kind = classify(raw.limitWindowSeconds)
            let window = try makeWindow(raw, kind: kind, now: now, id: kind.accountID, title: kind.accountTitle)
            classified.append((kind, window))
        }
        return classified.sorted { $0.0.sortOrder < $1.0.sortOrder }.map(\.1)
    }

    private static func additionalWindows(_ limit: AdditionalLimit, now: Date) throws(ProviderError) -> [UsageWindow] {
        let name = [limit.limitName, limit.normalModelSlug, limit.meteredFeature]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Additional limit"
        let slug = slugify(name)
        var classified: [(WindowClass, UsageWindow)] = []
        for raw in [limit.rateLimit?.primaryWindow, limit.rateLimit?.secondaryWindow].compactMap({ $0 }) {
            let kind = classify(raw.limitWindowSeconds)
            let window = try makeWindow(
                raw,
                kind: kind,
                now: now,
                id: "openai.\(slug).\(kind.additionalSuffix)",
                title: kind.additionalTitle(name),
                perModel: true
            )
            classified.append((kind, window))
        }
        return classified.sorted { $0.0.sortOrder < $1.0.sortOrder }.map(\.1)
    }

    private static func makeWindow(
        _ raw: Window,
        kind: WindowClass,
        now: Date,
        id: String,
        title: String,
        perModel: Bool = false
    ) throws(ProviderError) -> UsageWindow {
        guard let percent = raw.usedPercent, percent.isFinite else { throw .decoding("openai_percent") }
        let resetsAt = VendorDates.epoch(raw.resetAt)
            ?? raw.resetAfterSeconds.flatMap { $0.isFinite && $0 >= 0 ? now.addingTimeInterval($0) : nil }
        return UsageWindow(
            id: id,
            title: title,
            kind: kind.usageKind(perModel: perModel),
            usedPercent: percent,
            resetsAt: resetsAt,
            windowDuration: raw.limitWindowSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        )
    }

    static func classify(_ seconds: Double?) -> WindowClass {
        guard let seconds, seconds.isFinite, seconds > 0 else { return .unknown }
        if abs(seconds - sessionSeconds) <= sessionSeconds * 0.1 { return .session }
        if abs(seconds - weeklySeconds) <= weeklySeconds * 0.1 { return .weekly }
        return .other(seconds: seconds)
    }

    static func slugify(_ text: String) -> String {
        var slug = ""
        var previousDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousDash = false
            } else if !previousDash {
                slug.append("-")
                previousDash = true
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "limit" : trimmed
    }

    enum WindowClass: Equatable {
        case session
        case weekly
        case other(seconds: Double)
        case unknown

        var sortOrder: Int {
            switch self {
            case .session: 0
            case .weekly: 1
            case .other: 2
            case .unknown: 3
            }
        }

        var accountID: String {
            switch self {
            case .session: "openai.session"
            case .weekly: "openai.weekly"
            case .other(let seconds): "openai.window.\(Int(seconds))"
            case .unknown: "openai.window.unknown"
            }
        }

        var accountTitle: String {
            switch self {
            case .session: "Current session"
            case .weekly: "Weekly usage limit"
            case .other(let seconds): "\(Self.spanLabel(seconds, long: true)) window"
            case .unknown: "Usage window"
            }
        }

        var additionalSuffix: String {
            switch self {
            case .session: "session"
            case .weekly: "weekly"
            case .other, .unknown: "window"
            }
        }

        func additionalTitle(_ name: String) -> String {
            switch self {
            case .session: "\(name) (5h)"
            case .weekly, .unknown: name
            case .other(let seconds): "\(name) (\(Self.spanLabel(seconds, long: false)))"
            }
        }

        func usageKind(perModel: Bool) -> UsageWindowKind {
            switch self {
            case .session: .session
            case .weekly: perModel ? .weeklyModel : .weekly
            case .other, .unknown: .other
            }
        }

        /// "30 day" / "30d" for anything from two days up, otherwise "12 hour" / "12h".
        static func spanLabel(_ seconds: Double, long: Bool) -> String {
            let hours = Int((seconds / 3600).rounded())
            if hours >= 48 {
                let days = Int((Double(hours) / 24).rounded())
                return long ? "\(days) day" : "\(days)d"
            }
            return long ? "\(hours) hour" : "\(hours)h"
        }
    }

    struct Payload: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let additionalRateLimits: [AdditionalLimit]?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case additionalRateLimits = "additional_rate_limits"
        }
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Double?
        let resetAfterSeconds: Double?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }

    struct AdditionalLimit: Decodable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?
        let normalModelSlug: String?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
            case normalModelSlug = "normal_model_slug"
        }
    }
}
