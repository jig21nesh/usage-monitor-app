import Foundation

/// Where the vendor CLIs keep their files. Injected so tests never touch the real home directory.
public struct UserEnvironment: Sendable {
    public let homeDirectory: URL
    public let variables: [String: String]

    public init(homeDirectory: URL, variables: [String: String] = [:]) {
        self.homeDirectory = homeDirectory
        self.variables = variables
    }

    public static func current() -> UserEnvironment {
        UserEnvironment(homeDirectory: realHomeDirectory(), variables: ProcessInfo.processInfo.environment)
    }

    /// Resolves a CLI home such as `CODEX_HOME` or `GROK_HOME`. Only an absolute path is honoured;
    /// anything else falls back to the default under the home directory, so a hostile or
    /// accidental relative value can never redirect reads.
    public func directory(overrideVariable: String, defaultRelativePath: String) -> URL {
        if let raw = variables[overrideVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.hasPrefix("/") {
            return URL(filePath: raw, directoryHint: .isDirectory).standardizedFileURL
        }
        return homeDirectory.appending(path: defaultRelativePath, directoryHint: .isDirectory)
    }

    /// Under App Sandbox `NSHomeDirectory()` is the container, so ask the passwd database instead (ADR 0002).
    static func realHomeDirectory() -> URL {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let suggested = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        var buffer = [CChar](repeating: 0, count: suggested > 0 ? suggested : 4096)
        let status = getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result)
        if status == 0, result != nil, let directory = entry.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
