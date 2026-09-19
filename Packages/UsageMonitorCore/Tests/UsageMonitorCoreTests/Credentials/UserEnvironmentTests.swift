import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("UserEnvironment")
struct UserEnvironmentTests {
    let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)

    private func plain(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    @Test func defaultsToPathUnderHome() {
        let environment = UserEnvironment(homeDirectory: home)
        let url = environment.directory(overrideVariable: "CODEX_HOME", defaultRelativePath: ".codex")
        #expect(plain(url) == "/Users/tester/.codex")
    }

    @Test func honoursAbsoluteOverride() {
        let environment = UserEnvironment(homeDirectory: home, variables: ["CODEX_HOME": "/opt/codex"])
        let url = environment.directory(overrideVariable: "CODEX_HOME", defaultRelativePath: ".codex")
        #expect(plain(url) == "/opt/codex")
    }

    @Test(arguments: ["relative/dir", "", "   ", "~/codex", "./codex"])
    func ignoresNonAbsoluteOverrides(value: String) {
        let environment = UserEnvironment(homeDirectory: home, variables: ["GROK_HOME": value])
        let url = environment.directory(overrideVariable: "GROK_HOME", defaultRelativePath: ".grok")
        #expect(plain(url) == "/Users/tester/.grok")
    }

    @Test func trimsWhitespaceAndCollapsesDotSegments() {
        let environment = UserEnvironment(homeDirectory: home, variables: ["CODEX_HOME": "  /opt/a/../codex/  "])
        let url = environment.directory(overrideVariable: "CODEX_HOME", defaultRelativePath: ".codex")
        #expect(plain(url) == "/opt/codex")
    }

    @Test func currentEnvironmentResolvesARealHome() {
        let environment = UserEnvironment.current()
        var isDirectory: ObjCBool = false
        #expect(environment.homeDirectory.path(percentEncoded: false).hasPrefix("/"))
        let path = environment.homeDirectory.path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(environment.variables["PATH"] != nil)
    }
}
