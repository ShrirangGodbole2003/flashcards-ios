import Foundation

/// Describes one API call. Feature data layers add static factories in extensions.
struct Endpoint: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    let path: String
    let method: Method
    var body: Data?
    /// `false` for /api/auth/*: the backend does not want a Bearer token there.
    var requiresAuth: Bool
    var timeout: TimeInterval?
    var headers: [String: String]

    init(path: String,
         method: Method,
         body: Data? = nil,
         requiresAuth: Bool = true,
         timeout: TimeInterval? = nil,
         headers: [String: String] = [:]) {
        self.path = path
        self.method = method
        self.body = body
        self.requiresAuth = requiresAuth
        self.timeout = timeout
        self.headers = headers
    }

    static func json<Body: Encodable>(path: String,
                                      method: Method = .post,
                                      body: Body,
                                      requiresAuth: Bool = true,
                                      timeout: TimeInterval? = nil) throws -> Endpoint {
        Endpoint(path: path,
                 method: method,
                 body: try JSONCoding.makeEncoder().encode(body),
                 requiresAuth: requiresAuth,
                 timeout: timeout)
    }

    func addingHeader(_ name: String, _ value: String) -> Endpoint {
        var copy = self
        copy.headers[name] = value
        return copy
    }
}
