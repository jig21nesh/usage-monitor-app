import Foundation
import Synchronization
import Testing
@testable import UsageMonitorCore

private struct StubCredential: Sendable, Hashable {
    let token: String
    let expiresAt: Date?
}

/// Hands out scripted results in order, repeating the last, and counts how often it is asked.
private final class ScriptedSource: CredentialSource, Sendable {
    let loads = CallCounter()
    private let results: Mutex<[Result<StubCredential, ProviderError>]>

    init(_ results: [Result<StubCredential, ProviderError>]) {
        self.results = Mutex(results)
    }

    func load() throws(ProviderError) -> StubCredential {
        loads.increment()
        let next = results.withLock { queue -> Result<StubCredential, ProviderError> in
            queue.count > 1 ? queue.removeFirst() : queue[0]
        }
        return try next.get()
    }
}

@Suite("CachedCredentialSource")
struct CachedCredentialSourceTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func credential(_ token: String, expiresIn seconds: TimeInterval?) -> StubCredential {
        StubCredential(token: token, expiresAt: seconds.map { start.addingTimeInterval($0) })
    }

    private func makeCache(
        _ results: [Result<StubCredential, ProviderError>],
        now: @escaping @Sendable () -> Date
    ) -> (CachedCredentialSource<ScriptedSource>, ScriptedSource) {
        let base = ScriptedSource(results)
        let cache = CachedCredentialSource(base, label: "test", expiry: { $0.expiresAt }, now: now)
        return (cache, base)
    }

    @Test func coldLoadReadsTheStoreOnceAndReturnsItUnchanged() throws {
        let expected = credential("t1", expiresIn: 3600)
        let (cache, base) = makeCache([.success(expected)], now: { [start] in start })
        let loaded = try cache.load()
        #expect(loaded == expected)
        #expect(base.loads.total == 1)
    }

    @Test func warmLoadDoesNotTouchTheStore() throws {
        let (cache, base) = makeCache([.success(credential("t1", expiresIn: 3600))], now: { [start] in start })
        _ = try cache.load()
        let second = try cache.load()
        let third = try cache.load()
        #expect(second.token == "t1")
        #expect(third.token == "t1")
        #expect(base.loads.total == 1)
    }

    @Test func credentialWithinGraceOfExpiryIsReadAgain() throws {
        let clock = Mutex(start)
        let (cache, base) = makeCache(
            [.success(credential("old", expiresIn: 600)), .success(credential("new", expiresIn: 7200))],
            now: { clock.withLock { $0 } }
        )
        #expect(try cache.load().token == "old")
        // Exactly 60 s before expiry is the boundary: re-read.
        clock.withLock { $0 = start.addingTimeInterval(540) }
        #expect(try cache.load().token == "new")
        #expect(base.loads.total == 2)
        #expect(try cache.load().token == "new")
        #expect(base.loads.total == 2)
    }

    @Test func credentialJustOutsideGraceIsServedFromMemory() throws {
        let clock = Mutex(start)
        let (cache, base) = makeCache(
            [.success(credential("t1", expiresIn: 600))],
            now: { clock.withLock { $0 } }
        )
        _ = try cache.load()
        clock.withLock { $0 = start.addingTimeInterval(539) }
        _ = try cache.load()
        #expect(base.loads.total == 1)
    }

    @Test func customGraceIsHonoured() throws {
        let clock = Mutex(start)
        let base = ScriptedSource([.success(credential("t1", expiresIn: 600))])
        let cache = CachedCredentialSource(
            base, label: "test", expiry: { $0.expiresAt }, now: { clock.withLock { $0 } }, grace: 300
        )
        _ = try cache.load()
        clock.withLock { $0 = start.addingTimeInterval(299) }
        _ = try cache.load()
        #expect(base.loads.total == 1)
        clock.withLock { $0 = start.addingTimeInterval(300) }
        _ = try cache.load()
        #expect(base.loads.total == 2)
    }

    @Test func forgetForcesTheNextLoadToReadTheStore() throws {
        let (cache, base) = makeCache(
            [.success(credential("t1", expiresIn: nil)), .success(credential("t2", expiresIn: nil))],
            now: { [start] in start }
        )
        #expect(try cache.load().token == "t1")
        cache.forget()
        #expect(try cache.load().token == "t2")
        #expect(base.loads.total == 2)
        #expect(try cache.load().token == "t2")
        #expect(base.loads.total == 2)
    }

    @Test func forgetBeforeAnyLoadIsHarmless() throws {
        let (cache, base) = makeCache([.success(credential("t1", expiresIn: nil))], now: { [start] in start })
        cache.forget()
        #expect(try cache.load().token == "t1")
        #expect(base.loads.total == 1)
    }

    @Test func errorsAreNeverCached() throws {
        let (cache, base) = makeCache(
            [.failure(.credentialsNotFound), .success(credential("t1", expiresIn: nil))],
            now: { [start] in start }
        )
        #expect(throws: ProviderError.credentialsNotFound) { try cache.load() }
        #expect(try cache.load().token == "t1")
        #expect(base.loads.total == 2)
    }

    @Test func expiredReportedByTheStorePropagatesEveryTime() {
        let (cache, base) = makeCache([.failure(.credentialsExpired)], now: { [start] in start })
        #expect(throws: ProviderError.credentialsExpired) { try cache.load() }
        #expect(throws: ProviderError.credentialsExpired) { try cache.load() }
        #expect(base.loads.total == 2)
    }

    @Test func unreadableStoreDoesNotPoisonALaterSuccess() throws {
        let (cache, base) = makeCache(
            [
                .failure(.credentialsUnreadable("keychain_access_denied")),
                .success(credential("t1", expiresIn: 3600)),
            ],
            now: { [start] in start }
        )
        #expect(throws: ProviderError.credentialsUnreadable("keychain_access_denied")) { try cache.load() }
        #expect(try cache.load().token == "t1")
        #expect(try cache.load().token == "t1")
        #expect(base.loads.total == 2)
    }

    @Test func pastExpiryFromTheStoreIsNeverServedFromMemory() throws {
        // A store handing out an already-expired token (stale file, skewed clock) is asked again
        // on every load instead of having the stale answer replayed.
        let (cache, base) = makeCache([.success(credential("stale", expiresIn: -1))], now: { [start] in start })
        _ = try cache.load()
        _ = try cache.load()
        #expect(base.loads.total == 2)
    }

    @Test func tokenWithoutExpiryStaysCachedAsTimePasses() throws {
        let clock = Mutex(start)
        let (cache, base) = makeCache(
            [.success(credential("t1", expiresIn: nil))],
            now: { clock.withLock { $0 } }
        )
        _ = try cache.load()
        clock.withLock { $0 = start.addingTimeInterval(30 * 86_400) }
        _ = try cache.load()
        #expect(base.loads.total == 1)
    }

    @Test func concurrentLoadsReadTheStoreOnce() async {
        let (cache, base) = makeCache([.success(credential("t1", expiresIn: 3600))], now: { [start] in start })
        let tokens = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<50 {
                group.addTask { try? cache.load().token }
            }
            var collected: [String?] = []
            for await token in group {
                collected.append(token)
            }
            return collected
        }
        #expect(tokens.count == 50)
        #expect(tokens.allSatisfy { $0 == "t1" })
        #expect(base.loads.total == 1)
    }

    @Test func defaultForgetOnAPlainSourceIsANoOp() throws {
        // Sources that hold nothing between calls inherit an empty `forget()`.
        let source = ScriptedSource([.success(credential("t1", expiresIn: nil))])
        source.forget()
        #expect(try source.load().token == "t1")
        #expect(source.loads.total == 1)
    }

    @Test func defaultGraceIsOneMinute() {
        #expect(CachedCredentialSource<ScriptedSource>.defaultGrace == 60)
    }
}
