//
//  OdxApiV2LiveTests.swift
//
//  Live tests for the v2 (JSON-2) API against ODXProxy 0.9.0+ in front of Odoo 19+.
//  Skipped (not failed) unless these environment variables are set:
//
//      ODX_V2_GATEWAY_URL   proxy base URL, e.g. http://127.0.0.1:3000
//      ODX_V2_API_KEY       proxy x-api-key
//      ODX_V2_ODOO_URL      Odoo base URL (Odoo 19+)
//      ODX_V2_ODOO_DB       database name
//      ODX_V2_ODOO_API_KEY  Odoo API key (scope rpc on Odoo 20+), not a password
//
//  The create/write/remove lifecycle additionally needs ODX_V2_ALLOW_WRITES=1,
//  because it creates and deletes a real res.partner.
//
//  These use env vars rather than TestCredentials.swift so they can target a
//  different proxy than the v1 integration suite. Both configure the shared
//  singleton, so when both are set run one at a time:
//      swift test --filter OdxApiV2Live
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

private enum V2Env {
    static let env = ProcessInfo.processInfo.environment
    static let gatewayURL = env["ODX_V2_GATEWAY_URL"] ?? ""
    static let apiKey = env["ODX_V2_API_KEY"] ?? ""
    static let odooURL = env["ODX_V2_ODOO_URL"] ?? ""
    static let odooDB = env["ODX_V2_ODOO_DB"] ?? ""
    static let odooAPIKey = env["ODX_V2_ODOO_API_KEY"] ?? ""
    static let allowWrites = env["ODX_V2_ALLOW_WRITES"] == "1"

    static var isConfigured: Bool {
        !gatewayURL.isEmpty && !apiKey.isEmpty && !odooURL.isEmpty && !odooDB.isEmpty && !odooAPIKey.isEmpty
    }

    static func configure() {
        // userId is required by OdxInstanceInfo but never sent by v2.
        let instance = OdxInstanceInfo(url: odooURL, userId: 0, db: odooDB, apiKey: odooAPIKey)
        OdxProxyClient.shared.configure(
            with: OdxProxyClientInfo(instance: instance, odxApiKey: apiKey, gatewayUrl: gatewayURL,
                                     defaultContext: OdxContext(lang: "en_US")),
            timeout: 30
        )
    }
}

private struct Partner: Codable, Sendable {
    let id: Int
    let name: String
}

private struct FieldInfo: Codable, Sendable {
    let type: String
}

/// Asserts `body` throws `.odooLogic` with the given Odoo HTTP status.
private func expectOdooStatus(_ status: Int, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("expected Odoo status \(status), but the call succeeded")
    } catch let error as OdxProxyError {
        #expect(error.odooStatus == status, "got \(error)")
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

@Suite("OdxApiV2 live (read-only)", .serialized,
       .disabled(if: !V2Env.isConfigured, "Set ODX_V2_* env vars to run"))
struct OdxApiV2LiveReadTests {

    init() { V2Env.configure() }

    @Test("version reports Odoo 19+ and isSupported is true")
    func version() async throws {
        let res = try await OdxApiV2.version()
        #expect((res.result?.major ?? 0) >= 19)
        #expect(try await OdxApiV2.isSupported())
    }

    @Test("searchRead, search and searchCount agree")
    func searchFamily() async throws {
        let rows: OdxServerResponse<[Partner]> = try await OdxApiV2.searchRead(
            model: "res.partner", domain: OdxParams([["active", "=", true]]), fields: ["name"], limit: 3, order: "id asc")
        let partners = try #require(rows.result)
        #expect(!partners.isEmpty)

        let ids = try await OdxApiV2.search(model: "res.partner", domain: OdxParams([["active", "=", true]]), limit: 3, order: "id asc")
        #expect(ids.result == partners.map(\.id))

        let count = try await OdxApiV2.searchCount(model: "res.partner", domain: OdxParams([["id", "in", partners.map(\.id)]]))
        #expect(count.result == partners.count)
    }

    @Test("read and fieldsGet")
    func readAndFields() async throws {
        let ids = try #require(try await OdxApiV2.search(model: "res.partner", domain: OdxParams([]), limit: 1).result)
        let first = try #require(ids.first)
        let read: OdxServerResponse<[Partner]> = try await OdxApiV2.read(model: "res.partner", ids: [first], fields: ["name"])
        #expect(read.result?.first?.id == first)

        let fields: OdxServerResponse<[String: FieldInfo]> = try await OdxApiV2.fieldsGet(
            model: "res.partner", allfields: ["name"], attributes: ["type"])
        #expect(fields.result?["name"]?.type == "char")
    }

    @Test("callMethod runs context_get with no arguments")
    func callMethod() async throws {
        let res: OdxServerResponse<[String: OdxParams]> = try await OdxApiV2.callMethod(model: "res.users", method: "context_get")
        #expect(res.result?["lang"] != nil)
    }

    @Test("Odoo errors surface as .odooLogic with odooStatus; -32007 as .invalidRequest")
    func errors() async throws {
        // ids on an @api.model method -> 422
        await expectOdooStatus(422) {
            let _: OdxServerResponse<[Int]> = try await OdxApiV2.callMethod(
                model: "res.partner", method: "search", ids: [1], kwargs: ["domain": OdxParams([])])
        }
        // unknown kwarg -> 422
        await expectOdooStatus(422) {
            let _: OdxServerResponse<Int> = try await OdxApiV2.callMethod(
                model: "res.partner", method: "search_count", kwargs: ["filter": OdxParams([])])
        }
        // unknown model -> 404
        await expectOdooStatus(404) {
            _ = try await OdxApiV2.searchCount(model: "no.such.model", domain: OdxParams([]))
        }
        // private method -> 403
        await expectOdooStatus(403) {
            let _: OdxServerResponse<Bool> = try await OdxApiV2.callMethod(
                model: "res.partner", method: "_compute_display_name", ids: [1])
        }
        // path-unsafe model -> rejected by the proxy before Odoo
        await #expect {
            _ = try await OdxApiV2.searchCount(model: "..", domain: OdxParams([]))
        } throws: { error in
            if case OdxProxyError.invalidRequest = error { return true }
            return false
        }
    }
}

@Suite("OdxApiV2 live (writes)", .serialized,
       .disabled(if: !(V2Env.isConfigured && V2Env.allowWrites), "Set ODX_V2_* and ODX_V2_ALLOW_WRITES=1 to run"))
struct OdxApiV2LiveWriteTests {

    init() { V2Env.configure() }

    @Test("createOne -> write -> read -> remove lifecycle on res.partner")
    func lifecycle() async throws {
        let created = try await OdxApiV2.createOne(
            model: "res.partner", values: OdxParams(["name": "ODX v2 Swift Test Partner"]))
        let id = try #require(created.result)

        let wrote = try await OdxApiV2.write(model: "res.partner", ids: [id], values: OdxParams(["name": "ODX v2 Swift Test Partner (edited)"]))
        #expect(wrote.result == true)

        let read: OdxServerResponse<[Partner]> = try await OdxApiV2.read(model: "res.partner", ids: [id], fields: ["name"])
        #expect(read.result?.first?.name == "ODX v2 Swift Test Partner (edited)")

        let removed = try await OdxApiV2.remove(model: "res.partner", ids: [id])
        #expect(removed.result == true)
        let count = try await OdxApiV2.searchCount(model: "res.partner", domain: OdxParams([["id", "=", id]]))
        #expect(count.result == 0)
    }

    @Test("create with a list returns one id per record, in order")
    func createMany() async throws {
        struct NewPartner: Encodable, Sendable { let name: String }
        let res = try await OdxApiV2.create(model: "res.partner", values: [NewPartner(name: "ODX v2 A"), NewPartner(name: "ODX v2 B")])
        let ids = try #require(res.result)
        #expect(ids.count == 2)
        _ = try await OdxApiV2.remove(model: "res.partner", ids: ids)
    }
}
