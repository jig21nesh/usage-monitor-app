import Foundation
import ServiceManagement

/// Launch-at-login through `SMAppService.mainApp`. The system owns the state; the app mirrors it.
protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

final class SMAppServiceLoginItemController: LoginItemControlling {
    private let service = SMAppService.mainApp

    var isEnabled: Bool { service.status == .enabled }
    var requiresApproval: Bool { service.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Used in UI-test mode so tests never touch the real login items list.
final class FakeLoginItemController: LoginItemControlling {
    var isEnabled = false
    var requiresApproval = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }

    func openSystemSettings() {}
}
