import Foundation
import Synchronization
@testable import UsageMonitorCore

final class TerminationFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}

/// Wakes the model on demand and records whether the model released its subscription.
final class FakeWakeSource: SystemWakeSource, Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let termination = TerminationFlag()

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.stream = stream
        self.continuation = continuation
        let flag = termination
        continuation.onTermination = { _ in flag.set() }
    }

    var isTerminated: Bool { termination.isSet }

    func wakes() -> AsyncStream<Void> { stream }

    func wake() {
        continuation.yield()
    }
}

/// Suspends inside `fetchUsage` until released, so tests can observe an in-flight poll.
final class GatedProvider: UsageProvider, Sendable {
    let id: ProviderID
    let fetches = CallCounter()
    private let result: Result<UsageSnapshot, ProviderError>
    private let gate: AsyncStream<Void>
    private let release: AsyncStream<Void>.Continuation

    init(id: ProviderID, result: Result<UsageSnapshot, ProviderError>) {
        self.id = id
        self.result = result
        (gate, release) = AsyncStream<Void>.makeStream()
    }

    func linkState() async -> LinkState { .unknown }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        fetches.increment()
        var iterator = gate.makeAsyncIterator()
        _ = await iterator.next()
        return try result.get()
    }

    func open() {
        release.yield()
    }
}

/// Yields until the condition holds or the budget runs out; never sleeps on the wall clock.
func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
    for _ in 0..<20_000 where !condition() {
        await Task.yield()
    }
}
