import Foundation

enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case transport(URLError.Code)
    /// HTTP 401. On auth endpoints this means "wrong credentials / bad refresh token".
    case unauthorized(ProblemDetail?)
    case http(status: Int, problem: ProblemDetail?)
    case decoding(String)
    /// The refresh token was rejected or missing: the user has to log in again.
    case sessionExpired
    case storage(String)

    var problem: ProblemDetail? {
        switch self {
        case .unauthorized(let problem): return problem
        case .http(_, let problem): return problem
        default: return nil
        }
    }

    /// Per-field messages from a 400 validation response.
    var fieldErrors: [String: String] { problem?.errors ?? [:] }

    var isConnectivityIssue: Bool {
        if case .transport(let code) = self {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(code)
        }
        return false
    }
}

extension APIError: LocalizedError {
    /// Text that is safe to show to the user.
    var errorDescription: String? {
        switch self {
        case .invalidURL, .invalidResponse, .decoding:
            return "Something went wrong talking to the server. Please try again."
        case .transport:
            return isConnectivityIssue
                ? "Can't reach the server. Check your connection and try again."
                : "A network error occurred. Please try again."
        case .unauthorized(let problem):
            return problem?.detail ?? "You are not authorized."
        case .http(let status, let problem):
            if let detail = problem?.detail { return detail }
            return status >= 500 ? "The server had a problem. Please try again later."
                                 : "The request failed (\(status))."
        case .sessionExpired:
            return "Your session has expired. Please log in again."
        case .storage:
            return "Couldn't access your saved session securely on this device."
        }
    }
}

extension Error {
    /// User-facing message for any error.
    var userMessage: String {
        (self as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
