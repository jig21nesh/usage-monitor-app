import AppKit
import Foundation

/// Emits once each time the Mac wakes so the model can refresh immediately instead of waiting
/// for the next scheduled poll (ADR 0001). Injected so tests can wake the model on demand.
public protocol SystemWakeSource: Sendable {
    func wakes() -> AsyncStream<Void>
}

/// Backed by `NSWorkspace.didWakeNotification`. The only AppKit dependency in Core.
public struct WorkspaceWakeSource: SystemWakeSource {
    public init() {}

    public func wakes() -> AsyncStream<Void> {
        let center = NSWorkspace.shared.notificationCenter
        let name = NSWorkspace.didWakeNotification
        return AsyncStream { continuation in
            let forwarder = Task {
                for await _ in center.notifications(named: name) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarder.cancel() }
        }
    }
}
