import Foundation

public enum OdxProxyError: Error, LocalizedError {
    // Client-side
    case notConfigured
    case invalidURL
    case networkError(Error)
    case invalidResponse(URLResponse?)
    case decodingError(Error)

    // Proxy-layer (SYSTEM_ARCHITECTURE.md §6)
    case authFailure(OdxServerErrorResponse)         // -32000  401  bad/missing x-api-key
    case invalidAction(OdxServerErrorResponse)       // -32001  400  action not in allowlist
    case missingFunctionName(OdxServerErrorResponse) // -32002  400  call_method without fn_name
    case upstreamTimeout(OdxServerErrorResponse)     // -32003  504  upstream Odoo timeout
    case upstreamConnect(OdxServerErrorResponse)     // -32004  502  upstream Odoo connection failure
    case proxyInternal(OdxServerErrorResponse)       // -32005  500  proxy internal error
    case licenseInvalid(OdxServerErrorResponse)      // 0       403  proxy license expired/invalid

    // Odoo-side logic error (200 OK envelope with an `error` object, code = Odoo's own)
    case odooLogic(OdxServerErrorResponse)

    // Fallback for codes the client doesn't recognize
    case serverError(OdxServerErrorResponse)

    /// Map a raw JSON-RPC error envelope to a typed `OdxProxyError`.
    /// `httpStatus` lets us distinguish Odoo logic errors (200 OK + error) from
    /// proxy-layer errors that happen to use an Odoo-style code.
    public static func from(_ response: OdxServerErrorResponse, httpStatus: Int?) -> OdxProxyError {
        switch response.code {
        case -32000: return .authFailure(response)
        case -32001: return .invalidAction(response)
        case -32002: return .missingFunctionName(response)
        case -32003: return .upstreamTimeout(response)
        case -32004: return .upstreamConnect(response)
        case -32005: return .proxyInternal(response)
        case 0:      return .licenseInvalid(response)
        default:
            if httpStatus == 200 {
                return .odooLogic(response)
            }
            return .serverError(response)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OdxProxyClient has not been configured. Call OdxProxyClient.shared.configure() before use."
        case .invalidURL:
            return "The gateway URL is invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from the server."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .authFailure(let r):
            return "Auth failure (\(r.code)): \(r.message)"
        case .invalidAction(let r):
            return "Invalid action (\(r.code)): \(r.message)"
        case .missingFunctionName(let r):
            return "Missing fn_name (\(r.code)): \(r.message)"
        case .upstreamTimeout(let r):
            return "Upstream Odoo timeout (\(r.code)): \(r.message)"
        case .upstreamConnect(let r):
            return "Upstream Odoo connection failure (\(r.code)): \(r.message)"
        case .proxyInternal(let r):
            return "Proxy internal error (\(r.code)): \(r.message)"
        case .licenseInvalid(let r):
            return "Proxy license invalid (\(r.code)): \(r.message)"
        case .odooLogic(let r):
            return "Odoo logic error (\(r.code)): \(r.message)"
        case .serverError(let r):
            return "Server error \(r.code): \(r.message)"
        }
    }
}
