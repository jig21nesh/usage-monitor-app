import Foundation
import Synchronization
@testable import UsageMonitorCore

final class CallCounter: Sendable {
    private let value = Mutex(0)

    var total: Int { value.withLock { $0 } }

    func increment() {
        value.withLock { $0 += 1 }
    }
}

/// Returns scripted results in order, repeating the last one. Counts fetches.
struct ScriptedProvider: UsageProvider {
    let id: ProviderID
    var link: LinkState = .unknown
    var results: [Result<UsageSnapshot, ProviderError>]
    let fetches = CallCounter()

    init(id: ProviderID, link: LinkState = .unknown, results: [Result<UsageSnapshot, ProviderError>]) {
        self.id = id
        self.link = link
        self.results = results
    }

    init(id: ProviderID, link: LinkState = .unknown, result: Result<UsageSnapshot, ProviderError>) {
        self.init(id: id, link: link, results: [result])
    }

    func linkState() async -> LinkState { link }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        let index = fetches.total
        fetches.increment()
        guard !results.isEmpty else { throw .network("scripted_empty") }
        return try results[min(index, results.count - 1)].get()
    }
}

extension UsageSnapshot {
    static func sample(
        provider: ProviderID,
        planName: String? = "Pro",
        usedPercent: Double = 42,
        fetchedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            planName: planName,
            windows: [
                UsageWindow(
                    id: "\(provider.rawValue).session",
                    title: "Current session",
                    kind: .session,
                    usedPercent: usedPercent,
                    resetsAt: fetchedAt.addingTimeInterval(3600),
                    windowDuration: 18_000
                ),
            ],
            fetchedAt: fetchedAt
        )
    }
}
