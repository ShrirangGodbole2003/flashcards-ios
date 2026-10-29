import Foundation

struct CredentialsRequestDTO: Encodable {
    let email: String
    let password: String
}

struct RefreshRequestDTO: Encodable {
    let refreshToken: String
}

struct UserDTO: Decodable {
    let id: Int
    let email: String
}

/// Response of POST /api/auth/register | login | refresh
struct AuthResponseDTO: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int          // access token lifetime in seconds
    let user: UserDTO

    func toSession(receivedAt: Date = Date()) -> AuthSession {
        AuthSession(
            tokens: AuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                accessTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(expiresIn))),
            user: AuthUser(id: user.id, email: user.email))
    }
}
