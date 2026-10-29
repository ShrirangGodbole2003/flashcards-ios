import Foundation
import Testing
@testable import flashcardsai_iOS

struct TokenManagerTests {
    private let clock = TestClock()

    private func makeManager(store: InMemorySecureStore,
                             refresher: StubRefresher) -> TokenManager {
        let clock = self.clock
        return TokenManager(store: store, refresher: refresher, leeway: 30, now: { clock.now })
    }

    private func session(access: String, refresh: String, expiresIn: TimeInterval = 900) -> AuthSession {
        TestData.session(access: access, refresh: refresh, expiresIn: expiresIn, now: clock.now)
    }

    // MARK: adopt / cached token

    @Test func adoptStoresRefreshTokenInSecureStoreAndServesAccessTokenFromMemory() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { _ in throw APIError.sessionExpired }
        let manager = makeManager(store: store, refresher: refresher)

        try await manager.adopt(session(access: "a1", refresh: "r1").tokens)

        #expect(store.refreshToken == "r1")
        #expect(try await manager.validAccessToken() == "a1")
        #expect(refresher.callCount == 0)
    }

    // MARK: refreshing

    @Test func refreshesWhenTheAccessTokenIsExpired() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { [self] _ in session(access: "a2", refresh: "r2") }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a1", refresh: "r1", expiresIn: 900).tokens)

        clock.advance(901)
        let token = try await manager.validAccessToken()

        #expect(token == "a2")
        #expect(refresher.receivedRefreshTokens == ["r1"])
    }

    @Test func refreshesSlightlyEarlyInsideTheLeewayWindow() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { [self] _ in session(access: "a2", refresh: "r2") }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a1", refresh: "r1", expiresIn: 900).tokens)

        clock.advance(880)          // 20s left < 30s leeway
        #expect(try await manager.validAccessToken() == "a2")
    }

    @Test func rotatedRefreshTokenIsPersistedAndUsedNextTime() async throws {
        let store = InMemorySecureStore()
        let counter = Counter()
        let refresher = StubRefresher { [self] _ in
            let n = counter.next()
            return session(access: "a\(n + 1)", refresh: "r\(n + 1)")
        }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a0", refresh: "r0").tokens)

        clock.advance(1000)
        _ = try await manager.validAccessToken()
        #expect(store.refreshToken == "r1")           // old one replaced, not kept

        clock.advance(1000)
        _ = try await manager.validAccessToken()
        #expect(refresher.receivedRefreshTokens == ["r0", "r1"])   // always the latest one
        #expect(store.refreshToken == "r2")
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let store = InMemorySecureStore([TokenManager.refreshTokenKey: "r0"])
        let refresher = StubRefresher { [self] _ in
            try await Task.sleep(for: .milliseconds(150))
            return session(access: "shared", refresh: "r1")
        }
        let manager = makeManager(store: store, refresher: refresher)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await manager.validAccessToken() } }
            var results: [String] = []
            for try await token in group { results.append(token) }
            return results
        }

        #expect(refresher.callCount == 1)               // a 2nd call would replay a dead token
        #expect(tokens == Array(repeating: "shared", count: 8))
    }

    @Test func aRejectedTokenAlreadyReplacedByAnotherCallerIsNotRefreshedAgain() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { [self] _ in session(access: "a2", refresh: "r2") }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a1", refresh: "r1").tokens)

        clock.advance(1000)
        _ = try await manager.validAccessToken()                       // someone refreshed -> a2
        let token = try await manager.refreshAccessToken(afterRejecting: "a1")

        #expect(token == "a2")
        #expect(refresher.callCount == 1)
    }

    @Test func rejectedCurrentTokenForcesARefresh() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { [self] _ in session(access: "a2", refresh: "r2") }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a1", refresh: "r1").tokens)

        // Server said 401 for a1 although the clock thinks it is fine (e.g. server clock skew)
        let token = try await manager.refreshAccessToken(afterRejecting: "a1")

        #expect(token == "a2")
        #expect(refresher.callCount == 1)
    }

    // MARK: failure handling

    @Test func serverRejectionEndsTheSessionAndAnnouncesIt() async throws {
        let store = InMemorySecureStore([TokenManager.refreshTokenKey: "dead"])
        let refresher = StubRefresher { _ in throw APIError.unauthorized(nil) }
        let manager = makeManager(store: store, refresher: refresher)

        await #expect(throws: APIError.sessionExpired) {
            _ = try await manager.validAccessToken()
        }

        #expect(store.refreshToken == nil)
        var iterator = manager.events.makeAsyncIterator()
        #expect(await iterator.next() == .expired)
    }

    @Test(arguments: [
        APIError.transport(.notConnectedToInternet),
        APIError.transport(.timedOut),
        APIError.http(status: 502, problem: nil),
    ])
    func transientFailuresKeepTheSession(error: APIError) async throws {
        let store = InMemorySecureStore([TokenManager.refreshTokenKey: "keep-me"])
        let refresher = StubRefresher { _ in throw error }
        let manager = makeManager(store: store, refresher: refresher)

        await #expect(throws: error) {
            _ = try await manager.validAccessToken()
        }

        #expect(store.refreshToken == "keep-me")     // offline must NOT log the user out
        #expect(await manager.hasStoredSession)
    }

    @Test func noStoredRefreshTokenMeansSessionExpired() async {
        let manager = makeManager(store: InMemorySecureStore(), refresher: StubRefresher { _ in throw APIError.sessionExpired })

        await #expect(throws: APIError.sessionExpired) {
            _ = try await manager.validAccessToken()
        }
    }

    // MARK: restore / clear

    @Test func restoreSessionReturnsNilWithoutAStoredToken() async throws {
        let refresher = StubRefresher { _ in throw APIError.sessionExpired }
        let manager = makeManager(store: InMemorySecureStore(), refresher: refresher)

        #expect(try await manager.restoreSession() == nil)
        #expect(refresher.callCount == 0)
    }

    @Test func restoreSessionRefreshesAndReturnsTheUser() async throws {
        let store = InMemorySecureStore([TokenManager.refreshTokenKey: "r0"])
        let refresher = StubRefresher { [self] _ in session(access: "a1", refresh: "r1") }
        let manager = makeManager(store: store, refresher: refresher)

        let restored = try await manager.restoreSession()

        #expect(restored?.user.email == "alice@example.com")
        #expect(store.refreshToken == "r1")
        #expect(try await manager.validAccessToken() == "a1")
        #expect(refresher.callCount == 1)
    }

    @Test func clearForgetsEverything() async throws {
        let store = InMemorySecureStore()
        let refresher = StubRefresher { _ in throw APIError.sessionExpired }
        let manager = makeManager(store: store, refresher: refresher)
        try await manager.adopt(session(access: "a1", refresh: "r1").tokens)

        await manager.clear()

        #expect(store.refreshToken == nil)
        #expect(await manager.hasStoredSession == false)
        await #expect(throws: APIError.sessionExpired) {
            _ = try await manager.validAccessToken()
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}
