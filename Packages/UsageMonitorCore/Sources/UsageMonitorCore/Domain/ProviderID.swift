import Foundation

/// The vendors the app can monitor. Raw values are persisted in settings; never rename them.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case claude
    case openAI = "openai"
    case grok
    case copilot
    case cursor
    case muse
    case opencodeGo = "opencode-go"

    /// The providers enabled for a fresh install before onboarding has detected anything.
    public static let defaultEnabled: [ProviderID] = [.claude, .openAI, .grok]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .grok: "Grok"
        case .copilot: "GitHub Copilot"
        case .cursor: "Cursor"
        case .muse: "Muse Code"
        case .opencodeGo: "OpenCode Go"
        }
    }

    /// The vendor CLI or app whose stored login the app reuses (ADR 0002, ADR 0008).
    public var credentialOrigin: String {
        switch self {
        case .claude: "Claude Code"
        case .openAI: "Codex CLI"
        case .grok: "Grok Build CLI"
        case .copilot: "GitHub CLI"
        case .cursor: "Cursor"
        case .muse: "Muse Code CLI"
        case .opencodeGo: "OpenCode CLI"
        }
    }

    /// Shown to the user when a provider needs (re)linking.
    public var loginCommand: String {
        switch self {
        case .claude: "claude login"
        case .openAI: "codex login"
        case .grok: "grok login"
        case .copilot: "gh auth login"
        case .cursor: "cursor-agent login"
        case .muse: "muse login"
        case .opencodeGo: "opencode auth login"
        }
    }

    /// Endpoints that are newest, least documented or most likely to change (ADR 0003).
    public var isExperimental: Bool {
        switch self {
        case .grok, .cursor, .muse: true
        case .claude, .openAI, .copilot, .opencodeGo: false
        }
    }
}
