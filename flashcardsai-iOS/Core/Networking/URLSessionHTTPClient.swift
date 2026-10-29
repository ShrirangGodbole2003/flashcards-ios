import Foundation

/// Plain `URLSession` transport. Knows nothing about tokens.
struct URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send(_ endpoint: Endpoint) async throws -> Data {
        let request = try makeRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.transport(error.code)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized(decodeProblem(from: data))
        default:
            throw APIError.http(status: http.statusCode, problem: decodeProblem(from: data))
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        let relativePath = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        let url = baseURL.appending(path: relativePath)

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout = endpoint.timeout {
            request.timeoutInterval = timeout
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func decodeProblem(from data: Data) -> ProblemDetail? {
        guard !data.isEmpty else { return nil }
        return try? JSONCoding.makeDecoder().decode(ProblemDetail.self, from: data)
    }
}
