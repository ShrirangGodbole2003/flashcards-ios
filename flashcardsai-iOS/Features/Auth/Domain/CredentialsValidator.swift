import Foundation

/// Client-side mirror of the backend's rules (RegisterRequest) so users get
/// instant feedback. The server remains the source of truth.
enum CredentialsValidator {
    static let minPasswordLength = 8
    static let maxPasswordBytes = 72      // BCrypt limit on the backend
    static let maxEmailLength = 254

    static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func emailError(_ raw: String) -> String? {
        let email = normalizedEmail(raw)
        if email.isEmpty { return "Enter your email." }
        if email.count > maxEmailLength { return "Email is too long." }

        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !email.contains(" ") else {
            return "Enter a valid email address."
        }
        return nil
    }

    static func passwordError(_ password: String) -> String? {
        if password.isEmpty { return "Enter a password." }
        if password.count < minPasswordLength { return "Use at least \(minPasswordLength) characters." }
        if password.utf8.count > maxPasswordBytes { return "Password is too long." }
        return nil
    }

    static func confirmationError(password: String, confirmation: String) -> String? {
        password == confirmation ? nil : "Passwords don't match."
    }
}
