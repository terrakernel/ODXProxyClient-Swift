//
//  OdxBrainTests.swift
//
//  Offline tests for ODXBrain (`/brain/v1/*`): the wire body, the error mapping,
//  result decoding, and the facts derivation. No credentials, no network, and no
//  use of `OdxProxyClient.shared`, so they always run.
//
//  Each suite maps to SYSTEM_ARCHITECTURE.md §7.2's "Definition of done".
//  Payloads are copied from a live ODXProxy 0.10.0 + ODXBrain 0.1.0.
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

private func wire(_ call: OdxBrainCall, id: String? = "req-1") throws -> [String: Any] {
    let data = try JSONEncoder().encode(OdxBrain.makeRequest(call, id: id))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func err(_ code: Int, _ message: String = "m", type: String? = nil) -> OdxServerErrorResponse {
    OdxServerErrorResponse(code: code, message: message, data: type.map { AnyCodable(["message": message, "type": $0]) })
}

// MARK: - Wire body

@Suite("OdxBrain wire format")
struct OdxBrainWireTests {

    @Test("resolveModel with only a query sends id + query, nothing else")
    func minimalBody() throws {
        let body = try wire(.resolveModel(query: "which invoice is not paid yet", odooVersion: nil, edition: nil, k: nil, extra: [:]))
        #expect(Set(body.keys) == ["id", "query"])
        #expect(body["id"] as? String == "req-1")
        #expect(body["query"] as? String == "which invoice is not paid yet")
    }

    @Test("Unset facts are omitted, never encoded as null")
    func noNulls() throws {
        let data = try JSONEncoder().encode(OdxBrain.makeRequest(
            .resolveSOP(query: "q", odooVersion: nil, edition: nil, installedModules: nil, company: nil, k: nil, extra: [:]), id: "x"))
        #expect(!String(decoding: data, as: UTF8.self).contains("null"))
    }

    @Test("resolveModel maps every parameter to ODXBrain's wire name")
    func resolveModelFields() throws {
        let body = try wire(.resolveModel(query: "q", odooVersion: "19.0", edition: .enterprise, k: 5, extra: [:]))
        #expect(Set(body.keys) == ["id", "query", "odoo_version", "edition", "k"])
        #expect(body["odoo_version"] as? String == "19.0")
        #expect(body["edition"] as? String == "enterprise")
        #expect(body["k"] as? Int == 5)
    }

    @Test("resolveSOP adds installed_modules and company")
    func resolveSOPFields() throws {
        let body = try wire(.resolveSOP(query: "q", odooVersion: "20.0", edition: .community,
                                        installedModules: ["account", "purchase"], company: "acme", k: 3, extra: [:]))
        #expect(Set(body.keys) == ["id", "query", "odoo_version", "edition", "installed_modules", "company", "k"])
        #expect(body["installed_modules"] as? [String] == ["account", "purchase"])
        #expect(body["company"] as? String == "acme")
        #expect(body["edition"] as? String == "community")
    }

    @Test("No odoo_instance is ever sent")
    func noOdooInstance() throws {
        let body = try wire(.resolveModel(query: "q", odooVersion: "19.0", edition: .enterprise, k: 1, extra: [:]))
        #expect(body["odoo_instance"] == nil)
    }

    @Test("extra fields pass through; named parameters win; an extra id is ignored")
    func extraPassthrough() throws {
        let body = try wire(.resolveModel(query: "real", odooVersion: nil, edition: nil, k: nil, extra: [
            "future_flag": .bool(true),
            "nested": .object(["a": .number(1)]),
            "query": .string("from extra"),
            "id": .string("from extra"),
        ]))
        #expect(body["future_flag"] as? Bool == true)
        #expect((body["nested"] as? [String: Any])?["a"] as? Int == 1)
        #expect(body["query"] as? String == "real")
        #expect(body["id"] as? String == "req-1")
    }

    @Test("A missing id is auto-generated")
    func autoId() throws {
        let body = try wire(.resolveModel(query: "q", odooVersion: nil, edition: nil, k: nil, extra: [:]), id: nil)
        #expect((body["id"] as? String)?.isEmpty == false)
    }
}

// MARK: - Error mapping

@Suite("OdxBrain error mapping")
struct OdxBrainErrorTests {

    @Test("501 -32008 is .brainNotInstalled, not retryable")
    func notInstalled501() {
        let e = OdxProxyError.fromBrain(err(-32008, type: "odxbrain_not_installed"), httpStatus: 501)
        guard case .brainNotInstalled = e else { Issue.record("got \(e)"); return }
        #expect(e.brainErrorType == "odxbrain_not_installed")
        #expect(!e.isRetryable)
    }

    @Test("A bare 404 on /brain/* (proxy < 0.10.0) is also .brainNotInstalled")
    func notInstalledBare404() {
        let e = OdxProxyError.fromBrainNonEnvelope(httpStatus: 404, body: Data())
        guard case .brainNotInstalled(let r) = e else { Issue.record("got \(e)"); return }
        #expect(r.code == 404)
        #expect(!e.isRetryable)
    }

    @Test("Plain-text 400/422 is .serverError carrying the body text")
    func plainText() {
        for (status, text) in [(400, "Failed to parse the request body as JSON: key must be a string at line 1 column 2"),
                               (422, "Failed to deserialize the JSON body into the target type: missing field `id` at line 1 column 13")] {
            let e = OdxProxyError.fromBrainNonEnvelope(httpStatus: status, body: Data(text.utf8))
            guard case .serverError(let r) = e else { Issue.record("got \(e)"); continue }
            #expect(r.code == status)
            #expect(r.message == text)
        }
    }

    @Test("-32009 unreachable and -32010 timeout are retryable")
    func retryable() {
        let unreachable = OdxProxyError.fromBrain(err(-32009), httpStatus: 502)
        let timeout = OdxProxyError.fromBrain(err(-32010), httpStatus: 504)
        guard case .brainUnreachable = unreachable, case .brainTimeout = timeout else {
            Issue.record("got \(unreachable), \(timeout)"); return
        }
        #expect(unreachable.isRetryable)
        #expect(timeout.isRetryable)
    }

    @Test("-32011 is .brainMisconfigured, distinct from the caller's .authFailure")
    func misconfigured() {
        let e = OdxProxyError.fromBrain(err(-32011), httpStatus: 502)
        guard case .brainMisconfigured = e else { Issue.record("got \(e)"); return }
        #expect(!e.isRetryable)
    }

    @Test("401 -32000 and 403 code 0 keep their existing cases on /brain/*")
    func authAndLicense() {
        guard case .authFailure = OdxProxyError.fromBrain(err(-32000), httpStatus: 401) else { Issue.record("401"); return }
        guard case .licenseInvalid = OdxProxyError.fromBrain(err(0, "Invalid License"), httpStatus: 403) else { Issue.record("403"); return }
    }

    @Test("HTTP 200 + ODXBrain status is .brainError with brainStatus and brainErrorType")
    func brainError() {
        for (code, type) in [(400, "invalid_request_error"), (503, "sops_unavailable"), (503, "corpus_unavailable"), (500, "internal_error")] {
            let e = OdxProxyError.fromBrain(err(code, type: type), httpStatus: 200)
            guard case .brainError = e else { Issue.record("got \(e)"); continue }
            #expect(e.brainStatus == code)
            #expect(e.brainErrorType == type)
            #expect(e.odooStatus == nil)
            #expect(!e.isRetryable)
        }
    }

    @Test("Off /brain/*, HTTP 200 + 400 is still .odooLogic")
    func odooRouteUnchanged() {
        let e = OdxProxyError.from(err(400), httpStatus: 200)
        guard case .odooLogic = e else { Issue.record("got \(e)"); return }
        #expect(e.brainStatus == nil)
        #expect(e.brainErrorType == nil)
    }

    @Test("An HTTP 200 error envelope decodes as error, never as an empty result")
    func errorEnvelope() throws {
        let res = try decode(OdxServerResponse<OdxBrainSOPResolution>.self, #"""
        {"jsonrpc":"2.0","id":"r3","error":{"code":503,"message":"no SOP snapshot loaded; start odxbrain with --sops PATH","data":{"message":"no SOP snapshot loaded; start odxbrain with --sops PATH","type":"sops_unavailable"}}}
        """#)
        #expect(res.result == nil)
        let error = try #require(res.error)
        #expect(OdxProxyError.fromBrain(error, httpStatus: 200).brainErrorType == "sops_unavailable")
    }
}

// MARK: - Results

private let resolveJSON = #"""
{"jsonrpc":"2.0","id":"r1","result":{"candidates":[{"model":"account.move","score":0.5130316019058228},{"model":"account.payment","score":0.492055743932724},{"model":"account.payment.term","score":0.4619874060153961,"provisional":true}],"corpus_version":"2026.09.4","dim":1024,"model":"bge-m3","usage":{"prompt_tokens":10},"version_unaudited":"19.0","excluded":[{"model":"account.invoice","reason":"removed in 13.0","successor":"account.move"}],"some_future_field":{"x":1}}}
"""#

private let sopJSON = #"""
{"jsonrpc":"2.0","id":"r2","result":{"candidates":[{"id":"vendor-bill-from-po","score":0.7754995822906494,"title":"Record a vendor bill from a received purchase order","version":"181c84a3b7906648"},{"id":"vendor-payment","score":0.7101830244064331,"title":"Register a vendor payment","version":"29828a95a64934a5"},{"id":"customer-credit-note","score":0.0001,"title":"Issue a credit note for a returned or disputed invoice","version":"395c597b2adccf8f"}],"dim":1024,"excluded":[{"id":"customer-invoice","reason":"needs module sale"}],"facts_missing":["odoo_version","edition","company"],"match":"none","model":"bge-m3","sops":{"generation":1,"root":"9660e95aec011de84e0af821e6859198ddea6fe35934a206e4e12231e9ebcdd7"},"usage":{"prompt_tokens":10}}}
"""#

@Suite("OdxBrain results")
struct OdxBrainResultTests {

    @Test("Model resolution: every candidate, in order, with conditional fields surfaced")
    func modelResolution() throws {
        let r = try #require(try decode(OdxServerResponse<OdxBrainModelResolution>.self, resolveJSON).result)
        #expect(r.candidates.map(\.model) == ["account.move", "account.payment", "account.payment.term"])
        #expect(r.candidates.map(\.provisional) == [false, false, true])
        #expect(r.embeddingModel == "bge-m3")
        #expect(r.dim == 1024)
        #expect(r.corpusVersion == "2026.09.4")
        #expect(r.usage?.promptTokens == 10)
        #expect(r.versionUnaudited == "19.0")
        #expect(r.filtered == nil)
        #expect(r.excluded.first?.successor == "account.move")
    }

    @Test("filtered: false and missing excluded decode")
    func unfiltered() throws {
        let r = try #require(try decode(OdxServerResponse<OdxBrainModelResolution>.self, #"""
        {"jsonrpc":"2.0","id":"r1b","result":{"candidates":[{"model":"res.partner","score":0.57}],"corpus_version":"2026.09.4","dim":1024,"filtered":false,"model":"bge-m3","usage":{"prompt_tokens":5}}}
        """#).result)
        #expect(r.filtered == false)
        #expect(r.excluded.isEmpty)
        #expect(r.versionUnaudited == nil)
    }

    @Test("Unknown fields survive in raw, and encoding writes raw back")
    func rawKept() throws {
        let r = try #require(try decode(OdxServerResponse<OdxBrainModelResolution>.self, resolveJSON).result)
        guard case .object(let obj) = r.raw, case .object(let future)? = obj["some_future_field"] else {
            Issue.record("raw lost some_future_field"); return
        }
        guard case .number(1)? = future["x"] else { Issue.record("raw lost x"); return }

        let reencoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        #expect(reencoded["some_future_field"] != nil)
        #expect(reencoded["corpus_version"] as? String == "2026.09.4")
    }

    @Test("SOP resolution: candidates, sops set, match, excluded, facts_missing")
    func sopResolution() throws {
        let r = try #require(try decode(OdxServerResponse<OdxBrainSOPResolution>.self, sopJSON).result)
        #expect(r.candidates.map(\.id) == ["vendor-bill-from-po", "vendor-payment", "customer-credit-note"])
        #expect(r.candidates.last?.score == 0.0001, "a low score is still returned")
        #expect(r.candidates.first?.version == "181c84a3b7906648")
        #expect(r.sops.generation == 1)
        #expect(r.sops.root.count == 64)
        #expect(r.match == "none")
        #expect(r.excluded.first?.reason == "needs module sale")
        #expect(r.factsMissing == ["odoo_version", "edition", "company"])
        #expect(r.embeddingModel == "bge-m3")
    }

    @Test("A null id (e.g. /brain/v1/info) parses as an empty string")
    func nullId() throws {
        let res = try decode(OdxServerResponse<OdxParams>.self, #"""
        {"jsonrpc":"2.0","id":null,"result":{"service":"odxbrain","version":"0.1.0"}}
        """#)
        #expect(res.id == "")
        guard case .object(let obj)? = res.result, case .string("odxbrain")? = obj["service"] else {
            Issue.record("info result"); return
        }
    }
}

// MARK: - Feature probe

@Suite("OdxBrain feature probe")
struct OdxBrainAvailabilityTests {

    @Test("features.odxbrain true / false")
    func present() throws {
        let on = try decode(OdxServerResponse<OdxAboutInfo>.self, #"{"jsonrpc":"2.0","id":"about","result":{"build":"B","features":{"odxbrain":true},"version":"0.10.0"}}"#)
        let off = try decode(OdxServerResponse<OdxAboutInfo>.self, #"{"jsonrpc":"2.0","id":"about","result":{"build":"B","features":{"odxbrain":false},"version":"0.10.0"}}"#)
        #expect(on.result?.hasFeature("odxbrain") == true)
        #expect(off.result?.hasFeature("odxbrain") == false)
    }

    @Test("A missing features object (proxy < 0.10.0) or missing key reads as false")
    func missing() throws {
        let old = try decode(OdxServerResponse<OdxAboutInfo>.self, #"{"jsonrpc":"2.0","id":"about","result":{"build":"B","version":"0.9.0"}}"#)
        let other = try decode(OdxServerResponse<OdxAboutInfo>.self, #"{"jsonrpc":"2.0","id":"about","result":{"build":"B","features":{"other":{"nested":true}},"version":"0.11.0"}}"#)
        #expect(old.result?.features.isEmpty == true)
        #expect(old.result?.hasFeature("odxbrain") == false)
        #expect(other.result?.hasFeature("odxbrain") == false)
    }

    @Test("The existing two-argument OdxAboutInfo init still compiles and has no features")
    func sourceCompatibleInit() {
        #expect(OdxAboutInfo(build: "B", version: "0.9.0").features.isEmpty)
    }
}

// MARK: - Facts

@Suite("OdxBrain facts")
struct OdxBrainFactsTests {

    private func v2(_ info: [OdxParams], _ version: String) -> OdxBrainFacts {
        OdxBrainFacts.fromV2(OdxV2VersionInfo(versionInfo: info, version: version))
    }

    @Test("v2: version_info[:2] joined, enterprise from a packaged build")
    func v2Packaged() {
        let f = v2([.number(20), .number(0), .number(0), .string("final"), .number(0), .string("e")], "20.0+e-20260925")
        #expect(f == OdxBrainFacts(odooVersion: "20.0", edition: .enterprise))
    }

    @Test("v2: pre-release enterprise, community, and saas")
    func v2Variants() {
        #expect(v2([.number(20), .number(0)], "20.0alpha1+e").edition == .enterprise)
        #expect(v2([.number(19), .number(0)], "19.0") == OdxBrainFacts(odooVersion: "19.0", edition: .community))
        #expect(v2([.string("saas~18"), .number(3)], "saas~18.3+e").odooVersion == "saas~18.3")
    }

    @Test("v1: server_serie and +e in server_version")
    func v1() {
        let f = OdxBrainFacts.fromV1([
            "server_version": .string("20.0+e-20260925"),
            "server_serie": .string("20.0"),
        ])
        #expect(f == OdxBrainFacts(odooVersion: "20.0", edition: .enterprise))
        #expect(OdxBrainFacts.fromV1(["server_version": .string("17.0"), "server_serie": .string("17.0")]).edition == .community)
    }

    @Test("Missing facts stay nil instead of being guessed")
    func unknown() {
        #expect(OdxBrainFacts.fromV1([:]) == OdxBrainFacts())
        #expect(v2([], "") == OdxBrainFacts())
    }
}
