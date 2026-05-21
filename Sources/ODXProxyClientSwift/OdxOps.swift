import Foundation

/// Operational (non-data) endpoints exposed by the ODX proxy.
/// Kept separate from `OdxApi` per SYSTEM_ARCHITECTURE.md §7.10 — these are
/// ops endpoints, not part of the data API.
public enum OdxOps {

    private static func client() -> OdxProxyClient {
        return OdxProxyClient.shared
    }

    /// `GET /_/about` — returns the running proxy build's identifiers.
    /// Response is a JSON-RPC envelope wrapping `OdxAboutInfo`.
    public static func about() async throws -> OdxServerResponse<OdxAboutInfo> {
        return try await client().getAboutInfo()
    }

    /// `GET /_/license` — returns the proxy's license status.
    /// Response is a flat object (NOT a JSON-RPC envelope).
    public static func license() async throws -> OdxLicenseInfo {
        return try await client().getLicenseInfo()
    }
}
