import AppKit
import Foundation

/// Asks the user for their home folder through the standard open panel, which is what turns a
/// sandboxed folder into a security-scoped bookmark (ADR 0009). Nil means the user cancelled.
protocol HomeFolderPicking: AnyObject {
    func pickHomeFolder(expected: URL) async -> URL?
}

final class NSOpenPanelHomeFolderPicker: HomeFolderPicking {
    func pickHomeFolder(expected: URL) async -> URL? {
        AppActivation.bringToFront()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = expected
        panel.title = "Grant access to your home folder"
        panel.prompt = "Grant Access"
        panel.message = "Stay in \(expected.path(percentEncoded: false)) and click Grant Access. "
            + "The app reads the login files other tools saved there, read-only."
        let response = await panel.begin()
        guard response == .OK else { return nil }
        return panel.url
    }
}

/// Used in UI-test mode so tests never open a real panel; answers with the expected folder.
final class FakeHomeFolderPicker: HomeFolderPicking {
    func pickHomeFolder(expected: URL) async -> URL? {
        expected
    }
}
