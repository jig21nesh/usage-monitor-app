import Foundation

/// Maps ChatGPT `plan_type` values to the names the product shows.
enum OpenAIPlan {
    static func displayName(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else { return nil }
        switch rawValue {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "team": return "Team"
        case "business": return "Business"
        case "free": return "Free"
        case "go": return "Go"
        case "guest": return "Guest"
        case "enterprise", "ent26": return "Enterprise"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}
