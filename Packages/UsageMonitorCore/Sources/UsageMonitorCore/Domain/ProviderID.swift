import Foundation

/// The vendors the app can monitor. Raw values are persisted in settings; never rename them.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case claude
    case openAI = "openai"
    case grok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        }
    }

    /// The vendor CLI whose stored login the app reuses (ADR 0002).
    public var credentialOrigin: String {
        switch self {
        case .claude: "Claude Code"
        case .openAI: "Codex CLI"
        case .grok: "Grok Build CLI"
        }
    }

    /// Shown to the user when a provider needs (re)linking.
    public var loginCommand: String {
        switch self {
        case .claude: "claude login"
        case .openAI: "codex login"
        case .grok: "grok login"
        }
    }

    /// Grok's endpoint is the most fragile of the three (ADR 0003).
    public var isExperimental: Bool { self == .grok }
}
