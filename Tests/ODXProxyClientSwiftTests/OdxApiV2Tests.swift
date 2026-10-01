//
//  OdxApiV2Tests.swift
//
//  Offline tests for the v2 (JSON-2) API: the exact `/v2/odoo/execute` wire body
//  each `OdxApiV2` method produces, and the error mapping. No credentials, no
//  network, and no use of `OdxProxyClient.shared`, so they always run and can't
//  race the integration suites that configure the shared client.
//
//  The wire shapes are the ODXProxy contract in SYSTEM_ARCHITECTURE.md §4.6 / §7.1.
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

private let instance = OdxInstanceInfo(url: "https://erp.example.com", userId: 2, db: "prod", apiKey: "odoo-key")
private let defaultContext = OdxContext(lang: "en_US", tz: "Asia/Jakarta")

/// Encodes the full request for `call` and returns it as a JSON object.
private func wire(_ call: OdxV2Call, model: String = "res.partner", context: OdxContext? = nil, defaultContext: OdxContext? = defaultContext, id: String? = "req-1") throws -> [String: Any] {
    let request = OdxApiV2.makeRequest(model: model, method: call.method, kwargs: call.kwargs, context: context, instance: instance, defaultContext: defaultContext, id: id)
    let data = try JSONEncoder().encode(request)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func kwargs(_ body: [String: Any]) throws -> [String: Any] {
    try #require(body["kwargs"] as? [String: Any])
}

/// Compares two JSON values structurally (via JSONSerialization round-trip).
private func same(_ a: Any, _ b: Any) -> Bool {
    (a as AnyObject).isEqual(b)
}

private var defaultContextJSON: [String: Any] { ["lang": "en_US", "tz": "Asia/Jakarta"] }

private struct PartnerValues: Codable, Sendable {
    let name: String
    let comment: String?
}

@Suite("OdxApiV2 wire format")
struct OdxApiV2WireTests {

    @Test("Envelope: id, model_id, method, kwargs, and a user_id-free odoo_instance")
    func envelope() throws {
        let body = try wire(.searchRead(domain: OdxParams([["is_company", "=", true]]), fields: ["name"], offset: nil, limit: 5, order: nil))
        #expect(Set(body.keys) == ["id", "model_id", "method", "kwargs", "odoo_instance"])
        #expect(body["id"] as? String == "req-1")
        #expect(body["model_id"] as? String == "res.partner")
        #expect(body["method"] as? String == "search_read")
        #expect(same(body["odoo_instance"]!, ["url": "https://erp.example.com", "db": "prod", "api_key": "odoo-key"]))
        // No v1 fields.
        for v1Key in ["action", "params", "keyword", "fn_name"] {
            #expect(body[v1Key] == nil)
        }
        #expect(same(try kwargs(body), [
            "domain": [["is_company", "=", true]],
            "fields": ["name"],
            "limit": 5,
            "context": defaultContextJSON,
        ]))
    }

    @Test("A request id is generated when none is given")
    func generatedId() throws {
        let body = try wire(.remove(ids: [1]), id: nil)
        #expect((body["id"] as? String)?.isEmpty == false)
    }

    // Each method's kwargs, keyed exactly as Odoo's Python parameter names.
    @Test("search") func search() throws {
        let k = try kwargs(wire(.search(domain: OdxParams([]), offset: 10, limit: 3, order: "id desc")))
        #expect(same(k, ["domain": [Any](), "offset": 10, "limit": 3, "order": "id desc", "context": defaultContextJSON]))
    }

    @Test("search_count") func searchCount() throws {
        let k = try kwargs(wire(.searchCount(domain: OdxParams([["active", "=", true]]), limit: nil)))
        #expect(same(k, ["domain": [["active", "=", true]], "context": defaultContextJSON]))
    }

    @Test("read sends ids") func read() throws {
        let k = try kwargs(wire(.read(ids: [3, 4], fields: ["name"], load: nil)))
        #expect(same(k, ["ids": [3, 4], "fields": ["name"], "context": defaultContextJSON]))
    }

    @Test("fields_get uses allfields/attributes") func fieldsGet() throws {
        let k = try kwargs(wire(.fieldsGet(allfields: ["name"], attributes: ["type"])))
        #expect(same(k, ["allfields": ["name"], "attributes": ["type"], "context": defaultContextJSON]))
    }

    @Test("create sends vals_list as an array, from OdxParams or a Codable struct")
    func create() throws {
        let fromParams = try kwargs(wire(.create(values: [OdxParams(["name": "A"]), OdxParams(["name": "B"])])))
        #expect(same(fromParams["vals_list"]!, [["name": "A"], ["name": "B"]]))
        let fromStruct = try kwargs(wire(.create(values: [PartnerValues(name: "A", comment: "x")])))
        #expect(same(fromStruct["vals_list"]!, [["name": "A", "comment": "x"]]))
    }

    @Test("write sends ids + vals") func write() throws {
        let k = try kwargs(wire(.write(ids: [7], values: OdxParams(["comment": "x"]))))
        #expect(same(k, ["ids": [7], "vals": ["comment": "x"], "context": defaultContextJSON]))
    }

    @Test("remove calls unlink with ids") func remove() throws {
        let body = try wire(.remove(ids: [7]))
        #expect(body["method"] as? String == "unlink")
        #expect(same(try kwargs(body), ["ids": [7], "context": defaultContextJSON]))
    }

    @Test("callMethod: named kwargs, ids only when given, kwargs[\"context\"] dropped")
    func callMethod() throws {
        let withIds = try wire(.callMethod("action_post", ids: [9], kwargs: [:]), model: "account.move")
        #expect(withIds["method"] as? String == "action_post")
        #expect(same(try kwargs(withIds), ["ids": [9], "context": defaultContextJSON]))

        let named = try kwargs(wire(.callMethod("name_search", ids: nil, kwargs: [
            "name": .string("Acm"), "limit": .number(5), "context": .object(["tz": .string("ignored")]),
        ])))
        #expect(same(named, ["name": "Acm", "limit": 5, "context": defaultContextJSON]))
    }

    @Test("nil arguments are omitted; @api.model methods never get ids")
    func omission() throws {
        let k = try kwargs(wire(.searchRead(domain: nil, fields: nil, offset: nil, limit: nil, order: nil)))
        #expect(same(k, ["context": defaultContextJSON]))
        for call in [
            OdxV2Call.search(domain: OdxParams([]), offset: nil, limit: nil, order: nil),
            .searchRead(domain: nil, fields: nil, offset: nil, limit: nil, order: nil),
            .searchCount(domain: OdxParams([]), limit: nil),
            .fieldsGet(allfields: nil, attributes: nil),
            .create(values: [OdxParams(["name": "A"])]),
        ] {
            #expect(try kwargs(wire(call))["ids"] == nil, "\(call.method) must not send ids")
        }
    }

    @Test("Call context is merged over the default context; call keys win")
    func contextMerge() throws {
        let k = try kwargs(wire(.searchCount(domain: OdxParams([]), limit: nil),
                                context: OdxContext(tz: "UTC", allowedCompanyIds: [1])))
        #expect(same(k["context"]!, ["lang": "en_US", "tz": "UTC", "allowed_company_ids": [1]]))
    }

    @Test("context is omitted when neither default nor call context is set")
    func noContext() throws {
        let k = try kwargs(wire(.remove(ids: [1]), defaultContext: nil))
        #expect(k["context"] == nil)
    }

    @Test("OdxContext extra keys pass through verbatim")
    func contextExtra() throws {
        let ctx = OdxContext(lang: "id_ID", extra: ["active_test": .bool(false)])
        let k = try kwargs(wire(.remove(ids: [1]), context: ctx, defaultContext: nil))
        #expect(same(k["context"]!, ["lang": "id_ID", "active_test": false]))
    }
}

@Suite("OdxApiV2 errors and version")
struct OdxApiV2ErrorTests {

    private func error(_ code: Int, http: Int, data: AnyCodable? = nil) -> OdxProxyError {
        OdxProxyError.from(OdxServerErrorResponse(code: code, message: "boom", data: data), httpStatus: http)
    }

    @Test("-32006 maps to .json2Unavailable even though it arrives on HTTP 200")
    func json2Unavailable() {
        guard case .json2Unavailable(let r) = error(-32006, http: 200) else {
            Issue.record("expected .json2Unavailable"); return
        }
        #expect(r.code == -32006)
    }

    @Test("-32007 maps to .invalidRequest")
    func invalidRequest() {
        guard case .invalidRequest = error(-32007, http: 400) else {
            Issue.record("expected .invalidRequest"); return
        }
    }

    @Test("Odoo statuses on a 200 stay .odooLogic and expose odooStatus",
          arguments: [401, 403, 404, 409, 422, 500, 502])
    func odooStatus(code: Int) {
        let e = error(code, http: 200)
        guard case .odooLogic = e else { Issue.record("expected .odooLogic for \(code)"); return }
        #expect(e.odooStatus == code)
        #expect(e.isRetryable == (code == 409))
    }

    @Test("v1-style Odoo codes (0 / 200) have no odooStatus")
    func v1Codes() {
        #expect(error(200, http: 200).odooStatus == nil)
    }

    @Test("A non-2xx 422 (proxy rejected the body) is .serverError, not .odooLogic")
    func proxy422() {
        let e = error(422, http: 422)
        guard case .serverError = e else { Issue.record("expected .serverError"); return }
        #expect(e.odooStatus == nil)
    }

    @Test("odooErrorName reads data.name")
    func odooErrorName() {
        let data = AnyCodable(["name": "odoo.exceptions.ValidationError", "message": "Name is required"] as [String: Any])
        #expect(error(422, http: 200, data: data).odooErrorName == "odoo.exceptions.ValidationError")
        #expect(error(422, http: 200).odooErrorName == nil)
    }

    @Test("isRetryable: upstream connect yes; timeout and auth no")
    func retryable() {
        #expect(error(-32004, http: 502).isRetryable)
        #expect(!error(-32003, http: 504).isRetryable)
        #expect(!error(-32000, http: 401).isRetryable)
    }

    @Test("OdxV2VersionInfo decodes /json/version and exposes major")
    func versionInfo() throws {
        let json = #"{"jsonrpc":"2.0","id":"v","result":{"version_info":[20,0,0,"final",0,"e"],"version":"20.0+e"}}"#
        let res = try JSONDecoder().decode(OdxServerResponse<OdxV2VersionInfo>.self, from: Data(json.utf8))
        #expect(res.result?.version == "20.0+e")
        #expect(res.result?.major == 20)
    }

    @Test("A -32006 envelope decodes and maps like the proxy sends it")
    func json2UnavailableEnvelope() throws {
        let json = #"{"jsonrpc":"2.0","id":"x","error":{"code":-32006,"message":"JSON-2 is not available"}}"#
        let res = try JSONDecoder().decode(OdxServerResponse<OdxV2VersionInfo>.self, from: Data(json.utf8))
        let err = try #require(res.error)
        guard case .json2Unavailable = OdxProxyError.from(err, httpStatus: 200) else {
            Issue.record("expected .json2Unavailable"); return
        }
    }
}
