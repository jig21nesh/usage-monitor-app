import Foundation
import Testing
@testable import UsageMonitorCore

/// Start-up probing and credential-cache invalidation (ADR 0002 amendment 2026-09-21).
@MainActor
@Suite("UsageMonitorModel credentials")
struct UsageMonitorModelCredentialTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let linked = LinkState.linked(AccountInfo(planName: nil, accountLabel: nil, origin: "test"))

    private func makeModel(
        providers: [any UsageProvider],
        enabling enabled: Set<ProviderID>,
        sleeper: RecordingSleeper = RecordingSleeper()
    ) -> UsageMonitorModel {
        var settings = AppSettings.default
        settings.enabledProviders = enabled
        let now = fixedNow
        return UsageMonitorModel(
            providers: providers,
            settingsStore: InMemorySettingsStore(settings),
            sleeper: sleeper,
            now: { now }
        )
    }

    private func provider(
        _ id: ProviderID,
        link: LinkState = .unknown,
        results: [Result<UsageSnapshot, ProviderError>]
    ) -> ScriptedProvider {
        ScriptedProvider(id: id, link: link, results: results)
    }

    @Test func startUpProbesOnlyEnabledProviders() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let copilot = provider(.copilot, link: linked, results: [.success(.sample(provider: .copilot))])
        let model = makeModel(providers: [claude, copilot], enabling: [.claude])

        model.start()
        await model.loopTask?.value

        #expect(claude.linkProbes.total == 1)
        #expect(copilot.linkProbes.total == 0)
        #expect(copilot.fetches.total == 0)
        // The first successful poll rewrites the link with the snapshot's plan, so only linkedness is stable.
        #expect(model.status(for: .claude)?.link.isLinked == true)
        #expect(model.status(for: .copilot)?.link == .unknown)
    }

    @Test func refreshLinkStatesWithoutASubsetProbesEveryProvider() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let copilot = provider(
            .copilot, link: .notLinked(.credentialsNotFound), results: [.success(.sample(provider: .copilot))]
        )
        let model = makeModel(providers: [claude, copilot], enabling: [.claude])

        await model.refreshLinkStates()

        #expect(claude.linkProbes.total == 1)
        #expect(copilot.linkProbes.total == 1)
        #expect(model.status(for: .copilot)?.link == .notLinked(.credentialsNotFound))
    }

    @Test func refreshLinkStatesWithASubsetSkipsTheOthers() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let copilot = provider(.copilot, link: linked, results: [.success(.sample(provider: .copilot))])
        let model = makeModel(providers: [claude, copilot], enabling: [.claude, .copilot])

        await model.refreshLinkStates(only: [.copilot])

        #expect(claude.linkProbes.total == 0)
        #expect(copilot.linkProbes.total == 1)
        #expect(model.status(for: .claude)?.link == .unknown)
        #expect(model.status(for: .copilot)?.link == linked)
    }

    @Test func emptySubsetProbesNothing() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let model = makeModel(providers: [claude], enabling: [])

        model.start()
        await model.loopTask?.value

        #expect(claude.linkProbes.total == 0)
        #expect(claude.fetches.total == 0)
    }

    @Test func rejectedLoginDropsTheCachedCredential() async {
        let claude = provider(.claude, results: [.failure(.unauthorized(status: 401))])
        let model = makeModel(providers: [claude], enabling: [.claude])

        await model.refreshNow()

        #expect(claude.forgets.total == 1)
        #expect(model.status(for: .claude)?.link == .notLinked(.unauthorized(status: 401)))
    }

    @Test func forbiddenLoginDropsTheCachedCredential() async {
        let claude = provider(.claude, results: [.failure(.unauthorized(status: 403))])
        let model = makeModel(providers: [claude], enabling: [.claude])
        await model.refreshNow()
        #expect(claude.forgets.total == 1)
    }

    @Test func expiredLoginDropsTheCachedCredential() async {
        let grok = provider(.grok, results: [.failure(.credentialsExpired)])
        let model = makeModel(providers: [grok], enabling: [.grok])
        await model.refreshNow()
        #expect(grok.forgets.total == 1)
    }

    @Test func otherFailuresKeepTheCachedCredential() async {
        let claude = provider(.claude, results: [
            .failure(.serverError(status: 503)),
            .failure(.rateLimited(retryAfter: nil)),
            .failure(.network("offline")),
            .failure(.credentialsNotFound),
            .failure(.credentialsUnreadable("keychain_access_denied")),
            .failure(.decoding("shape")),
        ])
        let model = makeModel(providers: [claude], enabling: [.claude])

        for _ in 0..<6 {
            await model.refreshNow()
        }

        #expect(claude.fetches.total == 6)
        #expect(claude.forgets.total == 0)
    }

    @Test func successKeepsTheCachedCredential() async {
        let claude = provider(.claude, results: [.success(.sample(provider: .claude))])
        let model = makeModel(providers: [claude], enabling: [.claude])
        await model.refreshNow()
        await model.refreshNow()
        #expect(claude.forgets.total == 0)
    }

    @Test func relinkDropsTheCredentialBeforeProbing() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let model = makeModel(providers: [claude], enabling: [.claude])

        await model.relink(.claude)

        #expect(claude.forgets.total == 1)
        #expect(claude.linkProbes.total == 1)
        #expect(claude.fetches.total == 1)
    }

    @Test func relinkOfAnUnknownProviderTouchesNothing() async {
        let claude = provider(.claude, link: linked, results: [.success(.sample(provider: .claude))])
        let model = makeModel(providers: [claude], enabling: [.claude])
        await model.relink(.muse)
        #expect(claude.forgets.total == 0)
        #expect(claude.linkProbes.total == 0)
    }

    @Test func providerWithoutForgetSupportStillRelinks() async {
        let bare = BareProvider()
        bare.forgetCredentials()
        let model = makeModel(providers: [bare], enabling: [.grok])
        await model.relink(.grok)
        #expect(model.status(for: .grok)?.link == .notLinked(.credentialsNotFound))
    }
}

/// Uses the protocol's default `forgetCredentials()`.
private struct BareProvider: UsageProvider {
    let id = ProviderID.grok

    func linkState() async -> LinkState { .notLinked(.credentialsNotFound) }

    func fetchUsage() async throws(ProviderError) -> UsageSnapshot {
        throw .credentialsNotFound
    }
}
