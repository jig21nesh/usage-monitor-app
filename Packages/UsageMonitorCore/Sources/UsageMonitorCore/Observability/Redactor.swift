import Foundation

/// Masks anything that looks like a credential before text reaches a diagnostics report or a
/// bug report (ADR 0006). Defence in depth: nothing upstream should put a secret in text either.
public enum Redactor {
    static let patterns: [String] = [
        #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#,
        #"sk-ant-[A-Za-z0-9_-]+"#,
        #"sk-[A-Za-z0-9_-]{8,}"#,
        #"xai-[A-Za-z0-9_-]{8,}"#,
        #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
        #"(?i)sessionkey=[A-Za-z0-9._~+/=-]+"#,
    ]

    public static let mask = "[redacted]"

    public static func redact(_ text: String) -> String {
        var output = text
        for pattern in patterns {
            guard let regex = try? Regex(pattern) else { continue }
            output = output.replacing(regex, with: mask)
        }
        return output
    }
}
