//
//  EndpointURLBaselineTests.swift
//
//  Offline regression baseline for endpoint-URL construction.
//
//  WHY THIS EXISTS
//  ---------------
//  Swift 6.4 replaces Foundation's NSURL-backed URL parser with the unified
//  Swift `URL` implementation ("up to 4x faster URL parsing"). The public API
//  is unchanged, but the new parser is stricter/more RFC-3986-conformant, so
//  edge cases in `URL(string:)` and `URL.appendingPathComponent(_:)` *could*
//  shift. `OdxProxyClient.configure(with:)` builds its four endpoint URLs with
//  exactly those two operations (see OdxProxyClient.swift), passing path
//  components with a LEADING SLASH — the ambiguous case most likely to move.
//
//  These tests pin the output produced by the Swift 6.3.2 toolchain as the
//  baseline. If a future toolchain (6.4+) changes how these URLs render, this
//  suite fails loudly instead of the library silently hitting wrong endpoints.
//
//  This does NOT reach into OdxProxyClient's private Config — it mirrors the
//  exact construction steps from `configure(with:)`. If that logic ever
//  changes (trailing-slash strip, path components, URL(string:)), update the
//  `buildEndpoints` helper below to match.
//
//  Offline: no credentials, no network. Always runs.
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

private struct Endpoints: Equatable {
    let execute: String
    let version: String
    let about: String
    let license: String
}

/// Mirror of `OdxProxyClient.configure(with:)`'s URL-building steps.
/// Returns `nil` when `URL(string:)` rejects the gateway (→ `.invalidURL`).
private func buildEndpoints(gateway raw: String) -> Endpoints? {
    var gatewayUrlString = raw
    if gatewayUrlString.hasSuffix("/") {
        gatewayUrlString = String(gatewayUrlString.dropLast())
    }
    guard let gatewayUrl = URL(string: gatewayUrlString) else { return nil }
    return Endpoints(
        execute: gatewayUrl.appendingPathComponent("/api/odoo/execute").absoluteString,
        version: gatewayUrl.appendingPathComponent("/api/odoo/version").absoluteString,
        about:   gatewayUrl.appendingPathComponent("/_/about").absoluteString,
        license: gatewayUrl.appendingPathComponent("/_/license").absoluteString
    )
}

@Suite("Endpoint URL construction baseline")
struct EndpointURLBaselineTests {

    @Test("Default gateway resolves to the four documented endpoints")
    func defaultGateway_baseline() throws {
        let e = try #require(buildEndpoints(gateway: "https://gateway.odxproxy.io"))
        #expect(e.execute == "https://gateway.odxproxy.io/api/odoo/execute")
        #expect(e.version == "https://gateway.odxproxy.io/api/odoo/version")
        #expect(e.about   == "https://gateway.odxproxy.io/_/about")
        #expect(e.license == "https://gateway.odxproxy.io/_/license")
    }

    @Test("Trailing slash on the gateway is stripped, not doubled")
    func trailingSlashGateway_matchesDefault() throws {
        let withSlash = try #require(buildEndpoints(gateway: "https://gateway.odxproxy.io/"))
        let without   = try #require(buildEndpoints(gateway: "https://gateway.odxproxy.io"))
        #expect(withSlash == without)
        // No double slash between host and first path component.
        #expect(!withSlash.execute.contains("io//"))
    }

    @Test("Leading slash in the appended path component does not produce a double slash")
    func leadingSlashPathComponent_noDoubleSlash() throws {
        let e = try #require(buildEndpoints(gateway: "https://gateway.odxproxy.io"))
        for url in [e.execute, e.version, e.about, e.license] {
            // Only the scheme separator "://" may contain a double slash.
            let afterScheme = url.replacingOccurrences(of: "https://", with: "")
            #expect(!afterScheme.contains("//"), "unexpected double slash in \(url)")
        }
    }

    @Test("Gateway with a base subpath preserves the subpath under each endpoint")
    func subpathGateway_preservesPrefix() throws {
        let e = try #require(buildEndpoints(gateway: "https://example.com/proxy"))
        #expect(e.execute == "https://example.com/proxy/api/odoo/execute")
        #expect(e.version == "https://example.com/proxy/api/odoo/version")
        #expect(e.about   == "https://example.com/proxy/_/about")
        #expect(e.license == "https://example.com/proxy/_/license")
    }
}
