import Foundation
import Synchronization
@testable import UsageMonitorCore

/// Queue-based HTTP double: each `send` records the request and pops the next scripted response.
final class FakeHTTPClient: HTTPClient, Sendable {
    private struct State: Sendable {
        var queue: [Result<HTTPResponse, ProviderError>]
        var requests: [HTTPRequest] = []
    }

    private let state: Mutex<State>

    init(responses: [Result<HTTPResponse, ProviderError>] = []) {
        state = Mutex(State(queue: responses))
    }

    var requests: [HTTPRequest] { state.withLock { $0.requests } }

    func enqueue(_ result: Result<HTTPResponse, ProviderError>) {
        state.withLock { $0.queue.append(result) }
    }

    func enqueue(status: Int, body: Data = Data(), headers: [String: String] = [:]) {
        enqueue(.success(HTTPResponse(statusCode: status, headers: headers, body: body)))
    }

    func enqueue(status: Int, json: String, headers: [String: String] = [:]) {
        enqueue(status: status, body: Data(json.utf8), headers: headers)
    }

    func send(_ request: HTTPRequest) async throws(ProviderError) -> HTTPResponse {
        let next: Result<HTTPResponse, ProviderError>? = state.withLock { state in
            state.requests.append(request)
            return state.queue.isEmpty ? nil : state.queue.removeFirst()
        }
        guard let next else { throw .network("fake_no_response") }
        return try next.get()
    }
}
