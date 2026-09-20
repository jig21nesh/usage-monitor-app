import Foundation
import Testing
@testable import UsageMonitorCore

@Suite("CursorCredentialSource")
struct CursorCredentialSourceTests {
    private let cliFile = #"{"accessToken":"\#(CursorTestData.jwt())"}"#

    private let databaseValues: [String: String] = [
        CursorCredentialSource.accessTokenKey: CursorTestData.jwt(),
        CursorCredentialSource.emailKey: "someone@example.com",
        CursorCredentialSource.membershipKey: "pro",
        "cursorAuth/refreshToken": "REFRESHSECRET",
    ]

    @Test func readsTheAppDatabaseFirst() throws {
        let source = CursorTestData.source(database: FakeSQLiteReader(values: databaseValues))
        let credential = try source.load()
        #expect(credential.accessToken == CursorTestData.jwt())
        #expect(credential.subject == "user_01SECRETSUBJECT")
        #expect(credential.email == "someone@example.com")
        #expect(credential.membershipType == "pro")
        #expect(credential.planName == "Pro")
        #expect(credential.expiresAt == CursorTestData.now.addingTimeInterval(30 * 86_400))
    }

    @Test func databasePathIsUnderTheRealHome() {
        let source = CursorTestData.source()
        #expect(source.databaseURL.path(percentEncoded: false)
            == "/Users/tester/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        #expect(source.cliAuthURL.path(percentEncoded: false) == "/Users/tester/.cursor/auth.json")
    }

    @Test func fallsBackToKeychainWhenTheDatabaseIsMissing() throws {
        let items = [CursorCredentialSource.keychainService: Data(CursorTestData.jwt().utf8)]
        let keychain = FakeKeychainReader(items: items)
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), keychain: keychain)
        let credential = try source.load()
        #expect(credential.accessToken == CursorTestData.jwt())
        #expect(credential.email == nil)
        #expect(credential.membershipType == nil)
        #expect(credential.planName == nil)
    }

    @Test func fallsBackToTheCLIFileWhenDatabaseAndKeychainAreEmpty() throws {
        var files = FakeFileSystem()
        files.add(CursorTestData.home.appending(path: ".cursor/auth.json"), contents: cliFile)
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), fileSystem: files)
        #expect(try source.load().accessToken == CursorTestData.jwt())
    }

    @Test func emptyDatabaseRowFallsThroughToLaterSources() throws {
        var files = FakeFileSystem()
        files.add(CursorTestData.home.appending(path: ".cursor/auth.json"), contents: cliFile)
        let database = FakeSQLiteReader(values: [CursorCredentialSource.accessTokenKey: "   "])
        let source = CursorTestData.source(database: database, fileSystem: files)
        #expect(try source.load().accessToken == CursorTestData.jwt())
    }

    @Test func nothingAnywhereIsNotFound() {
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: .notFound))
        #expect(throws: ProviderError.credentialsNotFound) { try source.load() }
    }

    @Test func busyDatabaseIsReportedNotSkipped() {
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: .busy))
        #expect(throws: ProviderError.credentialsUnreadable("cursor_db_busy")) { try source.load() }
    }

    @Test(arguments: [SQLiteReadError.malformed, .cannotOpen(code: 14)])
    func otherDatabaseFailuresAreUnreadable(failure: SQLiteReadError) {
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: failure))
        #expect(throws: ProviderError.credentialsUnreadable("cursor_db")) { try source.load() }
    }

    @Test func keychainFailureIsUnreadable() {
        let keychain = FakeKeychainReader(error: .accessDenied(status: -25293))
        let source = CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), keychain: keychain)
        #expect(throws: ProviderError.credentialsUnreadable("cursor_keychain")) { try source.load() }
    }

    @Test func cliFileProblemsAreClassified() {
        let path = CursorTestData.home.appending(path: ".cursor/auth.json")
        var unreadable = FakeFileSystem()
        unreadable.unreadable.insert(FakeFileSystem.key(path))
        #expect(throws: ProviderError.credentialsUnreadable("cursor_file")) {
            try CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), fileSystem: unreadable).load()
        }
        var malformed = FakeFileSystem()
        malformed.add(path, contents: "not json")
        #expect(throws: ProviderError.credentialsMalformed("cursor_json")) {
            try CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), fileSystem: malformed).load()
        }
        var huge = FakeFileSystem()
        huge.files[FakeFileSystem.key(path)] = Data(count: 70_000)
        #expect(throws: ProviderError.credentialsMalformed("cursor_file_size")) {
            try CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), fileSystem: huge).load()
        }
        var tokenless = FakeFileSystem()
        tokenless.add(path, contents: #"{"accessToken":""}"#)
        #expect(throws: ProviderError.credentialsNotFound) {
            try CursorTestData.source(database: FakeSQLiteReader(failure: .notFound), fileSystem: tokenless).load()
        }
    }

    @Test(arguments: [-3600.0, 0.0, 59.0])
    func expiredOrNearlyExpiredTokensAreExpired(secondsLeft: TimeInterval) {
        let token = CursorTestData.jwt(expiresIn: secondsLeft)
        let database = FakeSQLiteReader(values: [CursorCredentialSource.accessTokenKey: token])
        #expect(throws: ProviderError.credentialsExpired) { try CursorTestData.source(database: database).load() }
    }

    @Test func tokenWithSixtyOneSecondsLeftStillCounts() throws {
        let token = CursorTestData.jwt(expiresIn: 61)
        let database = FakeSQLiteReader(values: [CursorCredentialSource.accessTokenKey: token])
        #expect(try CursorTestData.source(database: database).load().accessToken.isEmpty == false)
    }

    @Test func malformedTokenIsMalformed() {
        let database = FakeSQLiteReader(values: [CursorCredentialSource.accessTokenKey: "not.a.jwt.at.all"])
        #expect(throws: ProviderError.credentialsMalformed("cursor_token")) {
            try CursorTestData.source(database: database).load()
        }
    }

    @Test func tokenWithoutExpiryIsAccepted() throws {
        let payload = CursorTestData.base64URL(#"{"sub":"plain-subject"}"#)
        let token = "\(CursorTestData.base64URL(#"{"alg":"none"}"#)).\(payload).sig"
        let database = FakeSQLiteReader(values: [CursorCredentialSource.accessTokenKey: token])
        let credential = try CursorTestData.source(database: database).load()
        #expect(credential.expiresAt == nil)
        #expect(credential.subject == "plain-subject")
    }

    @Test func subjectPrefixIsStripped() {
        #expect(CursorCredentialSource.stripAuthPrefix("auth0|user_01ABC") == "user_01ABC")
        #expect(CursorCredentialSource.stripAuthPrefix("google-oauth2|123") == "123")
        #expect(CursorCredentialSource.stripAuthPrefix("bare") == "bare")
    }

    @Test(arguments: [
        ("pro", "Pro"), ("PRO", "Pro"), ("ultra", "Ultra"), ("free", "Free"), ("free_trial", "Free trial"),
        ("pro_plus", "Pro+"), ("enterprise", "Enterprise"), ("", "nil"), (" ", "nil"),
    ])
    func planNames(raw: String, expected: String) {
        let credential = CursorTestData.credential(membership: raw)
        #expect((credential.planName ?? "nil") == expected)
    }

    @Test func descriptionsNeverContainTheToken() {
        let credential = CursorTestData.credential()
        #expect(!credential.description.contains("SECRET"))
        #expect(!credential.debugDescription.contains("SECRET"))
        #expect(!String(reflecting: credential).contains("SECRET"))
        #expect(credential.description.contains("<redacted>"))
    }
}
