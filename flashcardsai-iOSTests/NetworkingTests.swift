import Foundation
import Testing
@testable import flashcardsai_iOS

// MARK: URLProtocol stub

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func readBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

// MARK: URLSessionHTTPClient (serialized: the stub handler is global)

@Suite(.serialized)
struct URLSessionHTTPClientTests {
    private let baseURL = URL(string: "http://localhost:8080")!

    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(baseURL: baseURL, session: URLSession(configuration: configuration))
    }

    private func respond(status: Int, body: String = "") {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
             Data(body.utf8))
        }
    }

    @Test func buildsRequestFromEndpoint() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        nonisolated(unsafe) var capturedBody: Data?
        StubURLProtocol.handler = { request in
            captured = request
            capturedBody = readBody(request)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let endpoint = try Endpoint.json(path: "/api/decks", body: CreateDeckRequestDTO(topic: "Swift", difficulty: .advanced), timeout: 90)
            .addingHeader("Authorization", "Bearer abc")

        _ = try await makeClient().send(endpoint)

        let request = try #require(captured)
        #expect(request.url?.absoluteString == "http://localhost:8080/api/decks")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(request.timeoutInterval == 90)
        let body = try #require(capturedBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object == ["topic": "Swift", "difficulty": "ADVANCED"])
    }

    @Test func decodesSuccessBody() async throws {
        respond(status: 200, body: #"[{"id":1,"topic":"T","difficulty":"BEGINNER","cardCount":4,"createdAt":"2026-10-20T15:35:11.123456Z"}]"#)
        let decks: [DeckSummaryDTO] = try await makeClient().send(Endpoint(path: "/api/decks", method: .get))
        #expect(decks.count == 1)
    }

    @Test func noContentReturnsEmptyData() async throws {
        respond(status: 204)
        let data = try await makeClient().send(Endpoint(path: "/api/decks/1", method: .delete))
        #expect(data.isEmpty)
    }

    @Test func unauthorizedCarriesProblemDetail() async {
        respond(status: 401, body: #"{"title":"Invalid Credentials","status":401,"detail":"Invalid email or password."}"#)
        do {
            _ = try await makeClient().send(Endpoint(path: "/api/auth/login", method: .post, requiresAuth: false))
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .unauthorized(let problem) = error else { Issue.record("wrong case \(error)"); return }
            #expect(problem?.detail == "Invalid email or password.")
            #expect(error.userMessage == "Invalid email or password.")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func validationErrorsExposeFieldMessages() async {
        respond(status: 400, body: #"{"title":"Validation Failed","status":400,"errors":{"email":"bad email"}}"#)
        do {
            _ = try await makeClient().send(Endpoint(path: "/x", method: .post))
            Issue.record("expected a throw")
        } catch let error as APIError {
            #expect(error.fieldErrors["email"] == "bad email")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func serverErrorWithoutBodyHasFriendlyMessage() async {
        respond(status: 500)
        do {
            _ = try await makeClient().send(Endpoint(path: "/x", method: .get))
            Issue.record("expected a throw")
        } catch let error as APIError {
            #expect(error == .http(status: 500, problem: nil))
            #expect(!error.userMessage.isEmpty)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func offlineMapsToTransportError() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().send(Endpoint(path: "/x", method: .get))
            Issue.record("expected a throw")
        } catch let error as APIError {
            #expect(error == .transport(.notConnectedToInternet))
            #expect(error.isConnectivityIssue)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func malformedBodyIsADecodingError() async {
        respond(status: 200, body: "not json")
        do {
            let _: [DeckSummaryDTO] = try await makeClient().send(Endpoint(path: "/x", method: .get))
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .decoding = error else { Issue.record("wrong case \(error)"); return }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}

// MARK: AuthorizedHTTPClient (token attach + refresh-and-retry-once)

struct AuthorizedHTTPClientTests {
    private func bearer(_ endpoint: Endpoint) -> String? { endpoint.headers["Authorization"] }

    @Test func attachesBearerTokenToProtectedEndpoints() async throws {
        let base = RecordingHTTPClient { _ in Data("ok".utf8) }
        let client = AuthorizedHTTPClient(base: base, tokens: StubTokenProvider())

        _ = try await client.send(Endpoint(path: "/api/decks", method: .get))

        #expect(base.requests.map(bearer) == ["Bearer old"])
    }

    @Test func authEndpointsNeverGetATokenOrTriggerRefresh() async throws {
        let base = RecordingHTTPClient { _ in Data() }
        let tokens = StubTokenProvider()
        let client = AuthorizedHTTPClient(base: base, tokens: tokens)

        _ = try await client.send(Endpoint(path: "/api/auth/login", method: .post, requiresAuth: false))

        #expect(base.requests.count == 1)
        #expect(bearer(base.requests[0]) == nil)
        #expect(tokens.rejectedTokens.isEmpty)
    }

    @Test func refreshesAndRetriesOnceAfter401() async throws {
        let base = RecordingHTTPClient { endpoint in
            if endpoint.headers["Authorization"] == "Bearer old" { throw APIError.unauthorized(nil) }
            return Data("done".utf8)
        }
        let tokens = StubTokenProvider()
        let client = AuthorizedHTTPClient(base: base, tokens: tokens)

        let data = try await client.send(Endpoint(path: "/api/decks", method: .get))

        #expect(String(decoding: data, as: UTF8.self) == "done")
        #expect(base.requests.map(bearer) == ["Bearer old", "Bearer new"])
        #expect(tokens.rejectedTokens == ["old"])
    }

    @Test func doesNotLoopWhenTheRetryIsAlsoRejected() async {
        let base = RecordingHTTPClient { _ in throw APIError.unauthorized(nil) }
        let client = AuthorizedHTTPClient(base: base, tokens: StubTokenProvider())

        await #expect(throws: APIError.unauthorized(nil)) {
            _ = try await client.send(Endpoint(path: "/api/decks", method: .get))
        }
        #expect(base.requests.count == 2)
    }

    @Test func propagatesSessionExpiredWhenRefreshFails() async {
        let base = RecordingHTTPClient { _ in throw APIError.unauthorized(nil) }
        let tokens = StubTokenProvider(refreshError: APIError.sessionExpired)
        let client = AuthorizedHTTPClient(base: base, tokens: tokens)

        await #expect(throws: APIError.sessionExpired) {
            _ = try await client.send(Endpoint(path: "/api/decks", method: .get))
        }
        #expect(base.requests.count == 1)
    }

    @Test func nonAuthErrorsAreNotRetried() async {
        let base = RecordingHTTPClient { _ in throw APIError.http(status: 502, problem: nil) }
        let tokens = StubTokenProvider()
        let client = AuthorizedHTTPClient(base: base, tokens: tokens)

        await #expect(throws: APIError.http(status: 502, problem: nil)) {
            _ = try await client.send(Endpoint(path: "/api/decks", method: .post))
        }
        #expect(base.requests.count == 1)
        #expect(tokens.rejectedTokens.isEmpty)
    }
}
