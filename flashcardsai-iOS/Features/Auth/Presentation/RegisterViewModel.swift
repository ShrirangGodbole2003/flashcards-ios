import Foundation
import Observation

@MainActor
@Observable
final class RegisterViewModel {
    var email = ""
    var password = ""
    var confirmation = ""

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var emailError: String?
    private(set) var passwordError: String?
    private(set) var confirmationError: String?

    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private let onAuthenticated: (AuthUser) -> Void

    init(authRepository: AuthRepository, onAuthenticated: @escaping (AuthUser) -> Void) {
        self.authRepository = authRepository
        self.onAuthenticated = onAuthenticated
    }

    var meetsLengthRule: Bool { password.count >= CredentialsValidator.minPasswordLength }

    func submit() async {
        guard !isLoading else { return }
        errorMessage = nil

        emailError = CredentialsValidator.emailError(email)
        passwordError = CredentialsValidator.passwordError(password)
        confirmationError = CredentialsValidator.confirmationError(password: password, confirmation: confirmation)
        guard emailError == nil, passwordError == nil, confirmationError == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await authRepository.register(
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
            if case .http(409, _) = apiError {
                emailError = "An account with this email already exists."
                return
            }
            emailError = apiError.fieldErrors["email"]
            passwordError = apiError.fieldErrors["password"]
            if emailError != nil || passwordError != nil { return }
        }
        errorMessage = error.userMessage
    }
}
