import Foundation
import Testing
@testable import UsageMonitorCore

/// The model owns the home folder grant's lifecycle: activate at start, re-probe after a change (ADR 0009).
@MainActor
@Suite("UsageMonitorModel home folder grant")
struct UsageMonitorModelHomeFolderTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let home = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    private let linked = LinkState.linked(AccountInfo(planName: nil, accountLabel: nil, origin: "test"))

    private func makeModel(
        providers: [any UsageProvider],
        homeFolder: FakeHomeFolderAccess,
        enabling enabled: Set<ProviderID> = [.openAI]
    ) -> UsageMonitorModel {
        var settings = AppSettings.default
        settings.enabledProviders = enabled
        let now = fixedNow
        return UsageMonitorModel(
            providers: providers,
            settingsStore: InMemorySettingsStore(settings),
            sleeper: RecordingSleeper(),
            now: { now },
            homeFolder: homeFolder
        )
    }

    @Test func initialStateComesFromTheAccessObject() {
        let access = FakeHomeFolderAccess(expectedDirectory: home, state: .stale)
        let model = makeModel(providers: [], homeFolder: access)
        #expect(model.homeFolderState == .stale)
        #expect(model.homeFolderDirectory == home)
    }

    @Test func defaultAccessIsAlwaysGranted() {
        let model = UsageMonitorModel(
            providers: [], settingsStore: InMemorySettingsStore(), sleeper: RecordingSleeper()
        )
        #expect(model.homeFolderState == .granted)
    }

    @Test func startActivatesTheGrantBeforePolling() async {
        let access = FakeHomeFolderAccess(expectedDirectory: home, state: .granted)
        let provider = ScriptedProvider(id: .openAI, link: linked, results: [.success(.sample(provider: .openAI))])
        let model = makeModel(providers: [provider], homeFolder: access)

        model.start()
        await model.loopTask?.value

        #expect(access.activations.total == 1)
        #expect(model.homeFolderState == .granted)
        #expect(provider.fetches.total == 1)
    }

    @Test func grantRefreshesEveryLinkStateAndPollsOnce() async throws {
        let access = FakeHomeFolderAccess(expectedDirectory: home)
        let openAI = ScriptedProvider(id: .openAI, link: linked, results: [.success(.sample(provider: .openAI))])
        let grok = ScriptedProvider(id: .grok, link: linked, results: [.success(.sample(provider: .grok))])
        let model = makeModel(providers: [openAI, grok], homeFolder: access, enabling: [.openAI])
        #expect(model.homeFolderState == .notGranted)

        try await model.grantHomeFolder(home)

        #expect(access.grants.total == 1)
        #expect(model.homeFolderState == .granted)
        #expect(openAI.linkProbes.total == 1)
        #expect(grok.linkProbes.total == 1, "disabled providers are probed too: the user is looking at the answer")
        #expect(openAI.fetches.total == 1)
        #expect(grok.fetches.total == 0, "polling still honours the enabled set")
        #expect(model.status(for: .openAI)?.snapshot != nil)
    }

    @Test func grantClearsBackoffFromEarlierFailures() async throws {
        let access = FakeHomeFolderAccess(expectedDirectory: home)
        let failure = ProviderError.credentialsUnreadable(ProviderError.homeFolderNotGranted)
        let openAI = ScriptedProvider(id: .openAI, link: .notLinked(failure), results: [
            .failure(failure), .failure(failure), .success(.sample(provider: .openAI)),
        ])
        let model = makeModel(providers: [openAI], homeFolder: access)
        await model.refreshNow()
        await model.refreshNow()
        #expect(model.status(for: .openAI)?.nextRetryAt != nil)

        try await model.grantHomeFolder(home)

        #expect(model.status(for: .openAI)?.lastError == nil)
        #expect(model.status(for: .openAI)?.nextRetryAt == nil)
        #expect(model.status(for: .openAI)?.snapshot != nil)
    }

    @Test func grantFailureLeavesTheStateUntouched() async {
        let access = FakeHomeFolderAccess(
            expectedDirectory: home, grantFailure: .wrongFolder(expected: "/Users/tester")
        )
        let openAI = ScriptedProvider(id: .openAI, link: linked, results: [.success(.sample(provider: .openAI))])
        let model = makeModel(providers: [openAI], homeFolder: access)

        await #expect(throws: HomeFolderGrantError.wrongFolder(expected: "/Users/tester")) {
            try await model.grantHomeFolder(URL(filePath: "/Users/tester/Documents"))
        }

        #expect(model.homeFolderState == .notGranted)
        #expect(openAI.linkProbes.total == 0)
        #expect(openAI.fetches.total == 0)
    }

    @Test func revokeReprobesWithoutPolling() async throws {
        let access = FakeHomeFolderAccess(expectedDirectory: home, state: .granted)
        let openAI = ScriptedProvider(id: .openAI, link: linked, results: [.success(.sample(provider: .openAI))])
        let model = makeModel(providers: [openAI], homeFolder: access)

        await model.revokeHomeFolder()

        #expect(access.revocations.total == 1)
        #expect(model.homeFolderState == .notGranted)
        #expect(openAI.linkProbes.total == 1)
        #expect(openAI.fetches.total == 0)
    }
}
