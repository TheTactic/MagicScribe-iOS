import Foundation

enum APIError: Error {
    case invalidResponse
    case server(status: Int, message: String?)
    case decoding
    case unauthorized
}
