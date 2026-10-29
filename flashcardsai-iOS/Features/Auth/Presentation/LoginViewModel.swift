import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
    var password = ""

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var emailError: String?
    private(set) var passwordError: String?

    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private let onAuthenticated: (AuthUser) -> Void

    init(authRepository: AuthRepository, onAuthenticated: @escaping (AuthUser) -> Void) {
        self.authRepository = authRepository
        self.onAuthenticated = onAuthenticated
    }

    func submit() async {
        guard !isLoading else { return }
        errorMessage = nil

        emailError = CredentialsValidator.emailError(email)
        passwordError = password.isEmpty ? "Enter your password." : nil
        guard emailError == nil, passwordError == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await authRepository.login(
                email: CredentialsValidator.normalizedEmail(email),
                password: password)
            onAuthenticated(user)
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        if let apiError = error as? APIError {
            emailError = apiError.fieldErrors["email"]
            passwordError = apiError.fieldErrors["password"]
            if emailError != nil || passwordError != nil { return }
        }
        errorMessage = error.userMessage
    }
}
