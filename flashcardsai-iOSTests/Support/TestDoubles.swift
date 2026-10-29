import Foundation
@testable import flashcardsai_iOS

// MARK: Secure store

final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    init(_ initial: [String: String] = [:]) { values = initial }

    func read(_ key: String) throws -> String? { lock.withLock { values[key] } }
    func save(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func delete(_ key: String) throws { lock.withLock { values[key] = nil } }

    var refreshToken: String? { lock.withLock { values[TokenManager.refreshTokenKey] } }
}

// MARK: Token refresher

final class StubRefresher: TokenRefresher, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private let handler: @Sendable (String) async throws -> AuthSession

    init(handler: @escaping @Sendable (String) async throws -> AuthSession) {
        self.handler = handler
    }

    var receivedRefreshTokens: [String] { lock.withLock { calls } }
    var callCount: Int { lock.withLock { calls.count } }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        lock.withLock { calls.append(refreshToken) }
        return try await handler(refreshToken)
    }
}

// MARK: Token provider (for AuthorizedHTTPClient tests)

final class StubTokenProvider: TokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var rejectedTokens: [String] = []
    let current: String
    let fresh: String
    let refreshError: Error?

    init(current: String = "old", fresh: String = "new", refreshError: Error? = nil) {
        self.current = current
        self.fresh = fresh
        self.refreshError = refreshError
    }

    func validAccessToken() async throws -> String { current }

    func refreshAccessToken(afterRejecting rejected: String) async throws -> String {
        lock.withLock { rejectedTokens.append(rejected) }
        if let refreshError { throw refreshError }
        return fresh
    }
}

// MARK: HTTP client

final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Endpoint] = []
    private let handler: @Sendable (Endpoint) async throws -> Data

    init(handler: @escaping @Sendable (Endpoint) async throws -> Data) {
        self.handler = handler
    }

    var requests: [Endpoint] { lock.withLock { recorded } }

    func send(_ endpoint: Endpoint) async throws -> Data {
        lock.withLock { recorded.append(endpoint) }
        return try await handler(endpoint)
    }
}

// MARK: Repositories

final class MockAuthRepository: AuthRepository, @unchecked Sendable {
    var loginResult: Result<AuthUser, Error> = .success(AuthUser(id: 1, email: "a@b.com"))
    var registerResult: Result<AuthUser, Error> = .success(AuthUser(id: 1, email: "a@b.com"))
    var restoreResult: Result<AuthUser?, Error> = .success(nil)
    private(set) var loginCalls: [(email: String, password: String)] = []
    private(set) var registerCalls: [(email: String, password: String)] = []
    private(set) var logoutCount = 0

    func login(email: String, password: String) async throws -> AuthUser {
        loginCalls.append((email, password))
        return try loginResult.get()
    }

    func register(email: String, password: String) async throws -> AuthUser {
        registerCalls.append((email, password))
        return try registerResult.get()
    }

    func restoreSession() async throws -> AuthUser? { try restoreResult.get() }
    func logout() async { logoutCount += 1 }
}

final class MockDeckRepository: DeckRepository, @unchecked Sendable {
    var decksResult: Result<[DeckSummary], Error> = .success([])
    var createResult: Result<Deck, Error> = .success(TestData.deck())
    private(set) var createCalls: [(topic: String, difficulty: Difficulty)] = []

    func fetchDecks() async throws -> [DeckSummary] { try decksResult.get() }
    func fetchDeck(id: Int) async throws -> Deck { TestData.deck(id: id) }
    func createDeck(topic: String, difficulty: Difficulty) async throws -> Deck {
        createCalls.append((topic, difficulty))
        return try createResult.get()
    }
    func deleteDeck(id: Int) async throws {}
}

// MARK: Data builders

enum TestData {
    static func session(access: String = "access-1",
                        refresh: String = "refresh-1",
                        expiresIn: TimeInterval = 900,
                        now: Date = Date()) -> AuthSession {
        AuthSession(tokens: AuthTokens(accessToken: access,
                                       refreshToken: refresh,
                                       accessTokenExpiresAt: now.addingTimeInterval(expiresIn)),
                    user: AuthUser(id: 7, email: "alice@example.com"))
    }

    static func qa(id: Int = 1) -> Card {
        Card(id: id, type: .qa, question: "Q\(id)", answer: "A\(id)", options: [],
             correctIndex: nil, explanation: "why", hint: "hint")
    }

    static func mcq(id: Int = 2, correctIndex: Int = 1) -> Card {
        Card(id: id, type: .mcq, question: "Q\(id)", answer: "B",
             options: ["A", "B", "C", "D"], correctIndex: correctIndex, explanation: nil, hint: nil)
    }

    static func trueFalse(id: Int = 3, answer: String = "True") -> Card {
        Card(id: id, type: .trueFalse, question: "Q\(id)", answer: answer, options: [],
             correctIndex: nil, explanation: nil, hint: nil)
    }

    static func deck(id: Int = 1, cards: [Card]? = nil) -> Deck {
        Deck(id: id, topic: "Spring", difficulty: .beginner, cards: cards ?? [qa(), mcq(), trueFalse()])
    }
}

/// Mutable clock for time-dependent tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}
