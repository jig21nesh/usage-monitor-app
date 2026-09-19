import Foundation
import Synchronization
@testable import UsageMonitorCore

final class InMemorySettingsStore: SettingsStore, Sendable {
    private struct State: Sendable {
        var settings: AppSettings
        var saves = 0
    }

    private let state: Mutex<State>

    init(_ settings: AppSettings = .default) {
        state = Mutex(State(settings: settings))
    }

    var current: AppSettings { state.withLock { $0.settings } }
    var saveCount: Int { state.withLock { $0.saves } }

    func load() -> AppSettings { current }

    func save(_ settings: AppSettings) {
        state.withLock { state in
            state.settings = settings
            state.saves += 1
        }
    }
}
