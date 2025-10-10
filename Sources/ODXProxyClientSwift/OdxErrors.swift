import Foundation

public enum OdxProxyError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case networkError(Error)
    case serverError(OdxServerErrorResponse)
    case invalidResponse(URLResponse?)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OdxProxyClient has not been configured. Call OdxProxyClient.shared.configure() before use."
        case .invalidURL:
            return "The gateway URL is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let errorResponse):
            return "Server error: \(errorResponse.code) - \(errorResponse.message)"
        case .invalidResponse:
            return "Invalid response from the server."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
