import Foundation

actor APIClient {
    // Debug points at the Mac's own local XAMPP server, which is how
    // Simulator (running on the same Mac) reaches `localhost` — a physical
    // device would need the Mac's LAN IP instead; not addressed yet since
    // testing is Simulator-only for now.
    #if DEBUG
    private let baseURL = URL(string: "http://localhost/magicscribe")!
    #else
    private let baseURL = URL(string: "https://magicscribe.tech")!
    #endif
    private let session: URLSession
    private let tokenStore: KeychainTokenStore

    init(session: URLSession = .shared, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func post<Body: Encodable, Response: Decodable>(
        _ endpoint: APIEndpoint,
        body: Body,
        authenticated: Bool = false
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        try attachAuthIfNeeded(&request, authenticated: authenticated)
        return try await send(request)
    }

    /// For endpoints expecting multipart/form-data — currently just
    /// speech.php's audio upload. `formFields` are sent as plain text parts
    /// alongside the file (e.g. `language`, `context`).
    func postMultipart<Response: Decodable>(
        _ endpoint: APIEndpoint,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        formFields: [String: String] = [:],
        authenticated: Bool = false
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try attachAuthIfNeeded(&request, authenticated: authenticated)

        var body = Data()
        for (key, value) in formFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await send(request)
    }

    private func attachAuthIfNeeded(_ request: inout URLRequest, authenticated: Bool) throws {
        guard authenticated else { return }
        guard let token = tokenStore.loadToken() else {
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            let message = try? JSONDecoder().decode(ServerErrorMessage.self, from: data).error
            throw APIError.server(status: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

private nonisolated struct ServerErrorMessage: Decodable {
    let error: String
}
