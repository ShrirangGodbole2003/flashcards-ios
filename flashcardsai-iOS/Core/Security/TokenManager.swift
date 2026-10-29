import Foundation
import OSLog

/// Calls the backend's refresh endpoint. Implemented by the auth data source,
/// which uses the *unauthenticated* HTTP client so there is no dependency cycle.
protocol TokenRefresher: Sendable {
    func refreshSession(refreshToken: String) async throws -> AuthSession
}

/// What `AuthorizedHTTPClient` needs from the token manager.
protocol TokenProviding: Sendable {
    /// A non-expired access token (refreshes first when needed).
    func validAccessToken() async throws -> String
    /// Called after the server answered 401 for `rejected`. Returns a token that
    /// is different from `rejected`, refreshing if no one else already did.
    func refreshAccessToken(afterRejecting rejected: String) async throws -> String
}

enum SessionEvent: Sendable, Equatable {
    /// The refresh token was rejected: the user must log in again.
    case expired
}

/// Single owner of the token lifecycle.
///  - access token: memory only
///  - refresh token: Keychain only (and replaced on EVERY refresh, the backend rotates it)
///  - concurrent refresh requests share ONE network call ("single flight"), because
///    the backend treats a reused refresh token as theft and revokes the whole session
///  - the session is cleared only when the server definitively rejects the refresh
///    token (401). Offline / timeout / 5xx keep the tokens so the user stays logged in.
///  - a Keychain READ ERROR is not "no session": it is thrown, the tokens are kept
///  - logging out (`clear()`) while a refresh is in flight discards that refresh's result
actor TokenManager: TokenProviding {
    static let refreshTokenKey = "refreshToken"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flashcardsai", category: "tokens")

    nonisolated let events: AsyncStream<SessionEvent>
    private let eventContinuation: AsyncStream<SessionEvent>.Continuation

    private let store: SecureStore
    private let refresher: TokenRefresher
    private let now: @Sendable () -> Date
    private let leeway: TimeInterval

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var refreshTask: Task<AuthSession, Error>?
    /// Bumped by `clear()`. A refresh remembers the value it started with; if it changed
    /// by the time the network call returns, the session was ended meanwhile (logout) and
    /// the result must be thrown away instead of written back.
    private var sessionGeneration = 0

    init(store: SecureStore,
         refresher: TokenRefresher,
         leeway: TimeInterval = 30,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.refresher = refresher
        self.leeway = leeway
        self.now = now
        (events, eventContinuation) = AsyncStream.makeStream(of: SessionEvent.self)
    }

    // MARK: Public API

    /// Best-effort convenience (read errors count as "no"). Logic that decides whether the
    /// user is logged out must use `readRefreshToken()` so errors aren't mistaken for absence.
    var hasStoredSession: Bool {
        ((try? store.read(Self.refreshTokenKey)) ?? nil) != nil
    }

    /// Used by logout to tell the server which token to revoke; best effort.
    var currentRefreshToken: String? {
        (try? store.read(Self.refreshTokenKey)) ?? nil
    }

    /// Call after a successful login / registration.
    func adopt(_ tokens: AuthTokens) throws {
        do {
            try store.save(tokens.refreshToken, for: Self.refreshTokenKey)
        } catch {
            throw APIError.storage(String(describing: error))
        }
        accessToken = tokens.accessToken
        accessTokenExpiry = tokens.accessTokenExpiresAt
    }

    /// App launch: exchange the stored refresh token for a fresh session.
    /// Returns nil when there is nothing stored (user must log in).
    func restoreSession() async throws -> AuthSession? {
        // A Keychain read ERROR throws (launch shows "try again") instead of looking like "no session".
        guard try readRefreshToken() != nil else { return nil }
        return try await performRefresh()
    }

    func validAccessToken() async throws -> String {
        if let token = accessToken, let expiry = accessTokenExpiry,
           expiry.timeIntervalSince(now()) > leeway {
            return token
        }
        return try await performRefresh().tokens.accessToken
    }

    func refreshAccessToken(afterRejecting rejected: String) async throws -> String {
        // Another caller may already have refreshed while this request was in flight.
        if let token = accessToken, token != rejected, let expiry = accessTokenExpiry,
           expiry.timeIntervalSince(now()) > leeway {
            return token
        }
        return try await performRefresh().tokens.accessToken
    }

    /// Forget everything (logout / session expired). Also invalidates a refresh that is
    /// still running: it is cancelled and, if it finishes anyway, its result is dropped.
    func clear() {
        sessionGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        accessTokenExpiry = nil
        do {
            try store.delete(Self.refreshTokenKey)
        } catch {
            // Memory is already cleared. Surface the failure in the logs: a refresh token that
            // survives logout would sign the user back in on the next launch.
            Self.logger.error("Could not delete the refresh token from secure storage: \(String(describing: error))")
        }
    }

    // MARK: Refresh (single flight)

    private func performRefresh() async throws -> AuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await self.runRefresh() }
        refreshTask = task
        return try await task.value
    }

    private func runRefresh() async throws -> AuthSession {
        let generation = sessionGeneration
        // Only release the slot if `clear()` hasn't already replaced it (a newer refresh may own it now).
        defer { if generation == sessionGeneration { refreshTask = nil } }

        guard let refreshToken = try readRefreshToken() else {
            expireSession()
            throw APIError.sessionExpired
        }

        let session: AuthSession
        do {
            session = try await refresher.refreshSession(refreshToken: refreshToken)
        } catch let error as APIError {
            if case .unauthorized = error {
                // A stale "expired" must not sign out someone who logged out and back in meanwhile.
                guard generation == sessionGeneration else { throw CancellationError() }
                expireSession()
                throw APIError.sessionExpired
            }
            throw error          // transient (offline, 5xx...): keep the tokens
        }

        // The user logged out while the request was in flight: do not write tokens back.
        guard generation == sessionGeneration else { throw CancellationError() }

        // The old refresh token is dead on the server now: persist the new one FIRST.
        do {
            try store.save(session.tokens.refreshToken, for: Self.refreshTokenKey)
        } catch {
            throw APIError.storage(String(describing: error))
        }
        accessToken = session.tokens.accessToken
        accessTokenExpiry = session.tokens.accessTokenExpiresAt
        return session
    }

    /// `nil` = nothing stored. Throws if the Keychain itself failed (the session must be kept).
    private func readRefreshToken() throws -> String? {
        do {
            return try store.read(Self.refreshTokenKey)
        } catch {
            Self.logger.error("Could not read the refresh token: \(String(describing: error))")
            throw APIError.storage(String(describing: error))
        }
    }

    private func expireSession() {
        clear()
        eventContinuation.yield(.expired)
    }
}
