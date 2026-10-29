import Foundation

/// Transport abstraction. Returns the raw body of a 2xx response (empty for 204)
/// and throws `APIError` otherwise. Decoding is layered on top (see extension).
protocol HTTPClient: Sendable {
    func send(_ endpoint: Endpoint) async throws -> Data
}

extension HTTPClient {
    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await send(endpoint)
        do {
            return try JSONCoding.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
