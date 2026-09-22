import Foundation
import UsageMonitorCore

/// The app's single composition root (ADR 0001). Views receive the model through the environment.
enum AppComposition {
    static let launchOptions = LaunchOptions.parse()
    static let model = makeModel(options: launchOptions)
    static let loginItems: any LoginItemControlling = makeLoginItems(options: launchOptions)
    static let homeFolderPicker: any HomeFolderPicking = makeHomeFolderPicker(options: launchOptions)

    static func makeModel(options: LaunchOptions) -> UsageMonitorModel {
        #if DEBUG
        if options.isUITesting {
            return PreviewComposition.makeModel(options: options)
        }
        #endif
        // File reads stay behind the user's home folder grant (ADR 0009); keychain reads do not need it.
        let homeFolder = BookmarkHomeFolderAccess(store: UserDefaultsBookmarkStore())
        return UsageMonitorModel(
            providers: ProviderRegistry.live(
                fileSystem: HomeFolderGatedFileSystem(base: LocalFileSystem(), access: homeFolder)
            ),
            settingsStore: UserDefaultsSettingsStore(),
            wakeSource: WorkspaceWakeSource(),
            homeFolder: homeFolder
        )
    }

    static func makeLoginItems(options: LaunchOptions) -> any LoginItemControlling {
        options.isUITesting ? FakeLoginItemController() : SMAppServiceLoginItemController()
    }

    static func makeHomeFolderPicker(options: LaunchOptions) -> any HomeFolderPicking {
        options.isUITesting ? FakeHomeFolderPicker() : NSOpenPanelHomeFolderPicker()
    }
}
