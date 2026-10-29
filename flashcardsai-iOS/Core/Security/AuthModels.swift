import Foundation

struct AuthTokens: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Date
}

struct AuthUser: Equatable, Hashable, Sendable {
    let id: Int
    let email: String
}

/// What the backend returns from register / login / refresh.
struct AuthSession: Equatable, Sendable {
    let tokens: AuthTokens
    let user: AuthUser
}
