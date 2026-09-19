import Foundation

/// The three vendors send reset times in three shapes; every mapper goes through here.
public enum VendorDates {
    /// Accepts RFC 3339 with or without fractional seconds, with `Z` or a numeric offset.
    public static func iso8601(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let date = try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)
            .timeZone(separator: .omitted)) {
            return date
        }
        if let date = try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)
            .timeZone(separator: .colon)) {
            return date
        }
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }
        return try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeZone(separator: .colon))
    }

    /// Unix epoch in seconds. Values that are clearly milliseconds (after the year 5138 in
    /// seconds) are scaled down, because Claude Code stores `expiresAt` in milliseconds.
    public static func epoch(_ value: Double?) -> Date? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
