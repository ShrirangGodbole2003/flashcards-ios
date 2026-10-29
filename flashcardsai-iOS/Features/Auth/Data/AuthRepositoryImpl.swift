import Foundation

struct AuthRepositoryImpl: AuthRepository {
    private let remote: AuthRemoteDataSource
    private let tokenManager: TokenManager

    init(remote: AuthRemoteDataSource, tokenManager: TokenManager) {
        self.remote = remote
        self.tokenManager = tokenManager
    }

    func register(email: String, password: String) async throws -> AuthUser {
        let session = try await remote.register(email: email, password: password)
        try await tokenManager.adopt(session.tokens)
        return session.user
    }

    func login(email: String, password: String) async throws -> AuthUser {
        let session = try await remote.login(email: email, password: password)
        try await tokenManager.adopt(session.tokens)
        return session.user
    }

    func restoreSession() async throws -> AuthUser? {
        try await tokenManager.restoreSession()?.user
    }

    func logout() async {
        // Capture the token, end the LOCAL session first (this also cancels a refresh that
        // might still be running), then tell the server on a best-effort basis. The user is
        // logged out on this device no matter what the network does.
        let refreshToken = await tokenManager.currentRefreshToken
        await tokenManager.clear()
        if let refreshToken {
            try? await remote.logout(refreshToken: refreshToken)
        }
    }
}
