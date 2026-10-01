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
    case json2Unavailable(OdxServerErrorResponse)    // -32006  200  v2: no JSON-2 (Odoo <= 18, use v1) or DB not selectable (dbfilter)
    case invalidRequest(OdxServerErrorResponse)      // -32007  400  v2: invalid model/method name, or db/api_key not header-safe

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
        case -32006: return .json2Unavailable(response)
        case -32007: return .invalidRequest(response)
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
        case .json2Unavailable(let r):
            return "JSON-2 unavailable (\(r.code)): \(r.message)"
        case .invalidRequest(let r):
            return "Invalid request (\(r.code)): \(r.message)"
        case .odooLogic(let r):
            return "Odoo logic error (\(r.code)): \(r.message)"
        case .serverError(let r):
            return "Server error \(r.code): \(r.message)"
        }
    }
}

// MARK: - Odoo status helpers

extension OdxProxyError {
    /// For `.odooLogic`, the HTTP status Odoo answered with, which the proxy forwards
    /// as the error `code`: 401 bad/expired Odoo API key, 403 access rights or private
    /// method, 404 unknown model/method or missing record, 409 lock conflict, 422
    /// validation error or bad arguments, 5xx Odoo server error. The proxy always
    /// forwards it on v2 (`OdxApiV2`); on v1 only when Odoo itself answered non-2xx.
    /// `nil` for every other case, and for v1's usual `0`/`200` codes.
    public var odooStatus: Int? {
        guard case .odooLogic(let r) = self, (400...599).contains(r.code) else { return nil }
        return r.code
    }

    /// For `.odooLogic`, Odoo's exception class from `data.name`
    /// (e.g. `"odoo.exceptions.ValidationError"`), when present.
    public var odooErrorName: String? {
        guard case .odooLogic(let r) = self,
              let data = r.data?.value as? [String: Any] else { return nil }
        return data["name"] as? String
    }

    /// Whether retrying the same call (with backoff) can succeed: a failed
    /// connection to Odoo, or an Odoo lock conflict (409). Timeouts are excluded
    /// because the upstream call may already have run; retry those yourself only
    /// for idempotent calls.
    public var isRetryable: Bool {
        switch self {
        case .upstreamConnect: return true
        case .odooLogic: return odooStatus == 409
        default: return false
        }
    }
}
