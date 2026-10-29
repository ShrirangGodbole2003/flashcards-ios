import Foundation

/// Talks to /api/auth/*. Built on the *unauthenticated* client: these endpoints
/// must not carry a Bearer token (see backend docs, section 8.1).
struct AuthRemoteDataSource: TokenRefresher {
    private let client: HTTPClient
    private let now: @Sendable () -> Date

    init(client: HTTPClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func register(email: String, password: String) async throws -> AuthSession {
        let endpoint = try Endpoint.json(path: "/api/auth/register",
                                         body: CredentialsRequestDTO(email: email, password: password),
                                         requiresAuth: false)
        let response: AuthResponseDTO = try await client.send(endpoint)
        return response.toSession(receivedAt: now())
    }

    func login(email: String, password: String) async throws -> AuthSession {
        let endpoint = try Endpoint.json(path: "/api/auth/login",
                                         body: CredentialsRequestDTO(email: email, password: password),
                                         requiresAuth: false)
        let response: AuthResponseDTO = try await client.send(endpoint)
        return response.toSession(receivedAt: now())
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let endpoint = try Endpoint.json(path: "/api/auth/refresh",
                                         body: RefreshRequestDTO(refreshToken: refreshToken),
                                         requiresAuth: false)
        let response: AuthResponseDTO = try await client.send(endpoint)
        return response.toSession(receivedAt: now())
    }

    func logout(refreshToken: String) async throws {
        // Short timeout: the user is already logged out locally, don't keep the UI waiting.
        let endpoint = try Endpoint.json(path: "/api/auth/logout",
                                         body: RefreshRequestDTO(refreshToken: refreshToken),
                                         requiresAuth: false,
                                         timeout: 5)
        _ = try await client.send(endpoint)
    }
}
