import Foundation

/// Decorator that adds `Authorization: Bearer ...` to protected endpoints and
/// transparently recovers from an expired access token:
///   401 -> ask the token provider for a fresh token -> retry the request ONCE.
/// If the refresh itself fails the provider throws `APIError.sessionExpired`.
struct AuthorizedHTTPClient: HTTPClient {
    private let base: HTTPClient
    private let tokens: TokenProviding

    init(base: HTTPClient, tokens: TokenProviding) {
        self.base = base
        self.tokens = tokens
    }

    func send(_ endpoint: Endpoint) async throws -> Data {
        guard endpoint.requiresAuth else { return try await base.send(endpoint) }

        let token = try await tokens.validAccessToken()
        do {
            return try await base.send(endpoint.addingHeader("Authorization", "Bearer \(token)"))
        } catch let error as APIError {
            guard case .unauthorized = error else { throw error }
            let fresh = try await tokens.refreshAccessToken(afterRejecting: token)
            return try await base.send(endpoint.addingHeader("Authorization", "Bearer \(fresh)"))
        }
    }
}
