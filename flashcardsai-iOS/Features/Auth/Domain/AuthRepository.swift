import Foundation

/// Domain contract for everything account-related. View models depend on this
/// protocol only, never on networking or Keychain details.
protocol AuthRepository: Sendable {
    func register(email: String, password: String) async throws -> AuthUser
    func login(email: String, password: String) async throws -> AuthUser
    /// Launch-time check. `nil` means there is no stored session.
    func restoreSession() async throws -> AuthUser?
    /// Best-effort server logout, always clears local credentials.
    func logout() async
}



