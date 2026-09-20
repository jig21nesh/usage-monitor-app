import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("MuseUsageProvider")
struct MuseUsageProviderTests {
    typealias Support = MuseTestSupport

    @Test func liveProviderHasTheExpectedIdentityAndPollFloor() {
        let provider = MuseUsageProvider.live(
            environment: Support.environment(),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Support.fetchedAt }
        )
        #expect(provider.id == .muse)
        #expect(provider.minimumPollInterval == .seconds(900))
        #expect(MuseUsageProvider.pollFloor == .seconds(900))
    }

    @Test func liveProviderWithoutAnyLoginIsNotLinked() async {
        let provider = MuseUsageProvider.live(
            environment: Support.environment(),
            http: FakeHTTPClient(),
            keychain: FakeKeychainReader(),
            fileSystem: FakeFileSystem(),
            now: { Support.fetchedAt }
        )
        #expect(await provider.linkState() == .notLinked(.credentialsNotFound))
        await #expect(throws: ProviderError.credentialsNotFound) { try await provider.fetchUsage() }
    }

    @Test func linkStateCarriesTheEmailAsLabelOnly() async {
        let provider = Support.provider(http: FakeHTTPClient(), credential: .success(Support.credential()))
        let expected = AccountInfo(planName: nil, accountLabel: "dev@example.com", origin: "Muse Code CLI")
        #expect(await provider.linkState() == .linked(expected))
    }

    @Test(arguments: [
        ProviderError.credentialsNotFound,
        .credentialsUnreadable("muse_file"),
        .credentialsMalformed("muse_token_kind"),
        .credentialsMalformed("muse_json"),
    ])
    func linkStateReportsEveryCredentialFailure(error: ProviderError) async {
        let provider = Support.provider(http: FakeHTTPClient(), credential: .failure(error))
        #expect(await provider.linkState() == .notLinked(error))
        await #expect(throws: error) { try await provider.fetchUsage() }
    }

    @Test func fetchMapsTheLiveShapeEndToEnd() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("key-active"))
        let snapshot = try await Support.provider(http: http).fetchUsage()
        #expect(snapshot.provider == .muse)
        #expect(snapshot.planName == "Power Usage")
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.fetchedAt == Support.fetchedAt)
        #expect(http.requests.count == 1)
    }

    @Test func httpAndDecodingFailuresPropagate() async throws {
        let unauthorized = FakeHTTPClient()
        unauthorized.enqueue(status: 401, json: "{}")
        await #expect(throws: ProviderError.unauthorized(status: 401)) {
            try await Support.provider(http: unauthorized).fetchUsage()
        }
        let garbage = FakeHTTPClient()
        garbage.enqueue(status: 200, body: try Support.fixture("key-malformed"))
        await #expect(throws: ProviderError.decoding("muse_json")) {
            try await Support.provider(http: garbage).fetchUsage()
        }
    }

    @Test func noFailurePathEverLeaksTheToken() async {
        let echoingBody = #"{"error":"invalid token dca:SECRETTOKEN123","detail":"SECRETTOKEN123"}"#
        let scripted: [Result<HTTPResponse, ProviderError>] = [
            .success(HTTPResponse(statusCode: 401, body: Data(echoingBody.utf8))),
            .success(HTTPResponse(statusCode: 429, headers: ["Retry-After": "60"], body: Data(echoingBody.utf8))),
            .success(HTTPResponse(statusCode: 500, body: Data(echoingBody.utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("not json SECRETTOKEN123".utf8))),
            .success(HTTPResponse(statusCode: 200, body: Data("{}".utf8))),
            .failure(.network("url_error_-1001")),
            .failure(.responseTooLarge(limit: 1)),
        ]
        for result in scripted {
            let provider = Support.provider(http: FakeHTTPClient(responses: [result]))
            do {
                let snapshot = try await provider.fetchUsage()
                #expect(!String(reflecting: snapshot).contains("SECRET"))
            } catch {
                let texts = [
                    String(describing: error), String(reflecting: error), error.logIdentifier, error.userMessage,
                ]
                for text in texts {
                    #expect(!text.contains("SECRET"))
                }
            }
        }
    }

    @Test func apiKeyInTheResponseNeverReachesTheSnapshot() async throws {
        let http = FakeHTTPClient()
        http.enqueue(status: 200, body: try Support.fixture("key-with-api-key"))
        let snapshot = try await Support.provider(http: http).fetchUsage()
        #expect(!String(reflecting: snapshot).contains("SECRETKEY"))
        #expect(snapshot.windows.count == 2)
    }
}
