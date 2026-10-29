import Foundation

/// RFC 9457 error body returned by every backend error.
/// Validation failures also carry `errors` (field -> message).
struct ProblemDetail: Decodable, Equatable, Sendable {
    let title: String?
    let status: Int?
    let detail: String?
    let instance: String?
    let errors: [String: String]?
}
