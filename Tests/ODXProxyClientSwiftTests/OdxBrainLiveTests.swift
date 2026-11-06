//
//  OdxBrainLiveTests.swift
//
//  Live tests for ODXBrain through ODXProxy 0.10.0+. Read-only: nothing is
//  written to Odoo. Skipped (not failed) unless ODX_BRAIN_LIVE=1 and:
//
//      ODX_PROXY_URL          proxy with ODXBrain + SOPs
//      ODX_PROXY_API_KEY      proxy x-api-key (shared by all three proxies)
//
//  Optional, each enabling more tests:
//
//      ODX_PROXY_NOBRAIN_URL  proxy without ODXBrain (the 501 path)
//      ODX_PROXY_NOSOPS_URL   proxy whose ODXBrain has no SOPs (sops_unavailable)
//      ODOO_URL               Odoo 19+ behind ODX_PROXY_URL, for brainFacts
//
//  These are the names ~/odx-it/sdk/env.sh exports. The ODX_BRAIN_LIVE opt-in
//  exists because those names are generic. This suite reconfigures the shared
//  singleton, so run it on its own:
//
//      source ~/odx-it/sdk/env.sh && ODX_BRAIN_LIVE=1 swift test --filter OdxBrainLive
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

private enum BrainEnv {
    static let env = ProcessInfo.processInfo.environment
    static let enabled = env["ODX_BRAIN_LIVE"] == "1"
    static let proxyURL = env["ODX_PROXY_URL"] ?? ""
    static let apiKey = env["ODX_PROXY_API_KEY"] ?? ""
    static let noBrainURL = env["ODX_PROXY_NOBRAIN_URL"] ?? ""
    static let noSOPsURL = env["ODX_PROXY_NOSOPS_URL"] ?? ""
    static let odooURL = env["ODOO_URL"] ?? ""

    static var isConfigured: Bool { enabled && !proxyURL.isEmpty && !apiKey.isEmpty }

    /// ODXBrain calls never send the instance, but OdxProxyClientInfo requires one.
    static func configure(_ gateway: String, apiKey: String = BrainEnv.apiKey) {
        let instance = OdxInstanceInfo(url: odooURL.isEmpty ? "http://unused.invalid" : odooURL,
                                       userId: 0, db: "unused", apiKey: "unused")
        OdxProxyClient.shared.configure(
            with: OdxProxyClientInfo(instance: instance, odxApiKey: apiKey, gatewayUrl: gateway),
            timeout: 30
        )
    }
}

@Suite("OdxBrain live", .serialized,
       .disabled(if: !BrainEnv.isConfigured, "Set ODX_BRAIN_LIVE=1, ODX_PROXY_URL and ODX_PROXY_API_KEY to run"))
struct OdxBrainLiveTests {

    @Test("isAvailable is true on a proxy with ODXBrain")
    func available() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        #expect(try await OdxBrain.isAvailable())
    }

    @Test("resolveModel returns ranked candidates and the corpus identifiers")
    func resolveModel() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        let res = try await OdxBrain.resolveModel(query: "which invoice is not paid yet",
                                                  odooVersion: "19.0", edition: .enterprise, id: "brain-live-1")
        #expect(res.id == "brain-live-1")
        let r = try #require(res.result)
        #expect(r.candidates.count == 3, "ODXBrain's default k")
        #expect(r.candidates.map(\.model).contains("account.move"))
        #expect(!r.embeddingModel.isEmpty)
        #expect(r.dim > 0)
        #expect(!r.corpusVersion.isEmpty)
        #expect(r.filtered == nil, "facts were sent")
    }

    @Test("Without facts, filtered is false; k and extra pass through")
    func unfilteredWithExtra() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        let r = try #require(try await OdxBrain.resolveModel(query: "customer addresses", k: 2,
                                                             extra: ["future_flag": .bool(true)]).result)
        #expect(r.filtered == false)
        #expect(r.candidates.count == 2)
        #expect(r.candidates.first?.model == "res.partner")
    }

    @Test("resolveSOP returns SOPs, the SOP set, and excluded / facts_missing")
    func resolveSOP() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        let r = try #require(try await OdxBrain.resolveSOP(
            query: "record a vendor bill from a purchase order",
            installedModules: ["account", "purchase"]).result)
        #expect(r.candidates.first?.id == "vendor-bill-from-po")
        #expect(r.sops.root.count == 64)
        #expect(r.factsMissing.contains("odoo_version"))
        #expect(r.excluded.contains { $0.id == "customer-invoice" })
    }

    @Test("ODXBrain's own 400 on HTTP 200 is .brainError")
    func badInput() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        do {
            _ = try await OdxBrain.resolveModel(query: "")
            Issue.record("expected .brainError")
        } catch let e as OdxProxyError {
            guard case .brainError = e else { Issue.record("got \(e)"); return }
            #expect(e.brainStatus == 400)
            #expect(e.brainErrorType == "invalid_request_error")
        }
    }

    @Test("info returns ODXBrain's /info with a null id")
    func info() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        let res = try await OdxBrain.info()
        #expect(res.id == "")
        guard case .object(let obj)? = res.result, case .string("odxbrain")? = obj["service"] else {
            Issue.record("unexpected info: \(String(describing: res.result))"); return
        }
    }

    @Test("A wrong proxy key is .authFailure")
    func wrongKey() async throws {
        BrainEnv.configure(BrainEnv.proxyURL, apiKey: "wrong-key")
        do {
            _ = try await OdxBrain.resolveModel(query: "customer addresses")
            Issue.record("expected .authFailure")
        } catch OdxProxyError.authFailure {
        }
    }

    @Test("No ODXBrain: isAvailable false, and calls throw .brainNotInstalled",
          .disabled(if: BrainEnv.noBrainURL.isEmpty, "Set ODX_PROXY_NOBRAIN_URL"))
    func notInstalled() async throws {
        BrainEnv.configure(BrainEnv.noBrainURL)
        #expect(try await OdxBrain.isAvailable() == false)
        do {
            _ = try await OdxBrain.resolveModel(query: "customer addresses")
            Issue.record("expected .brainNotInstalled")
        } catch let e as OdxProxyError {
            guard case .brainNotInstalled = e else { Issue.record("got \(e)"); return }
            #expect(e.brainErrorType == "odxbrain_not_installed")
            #expect(!e.isRetryable)
        }
    }

    @Test("No SOPs: resolveSOP throws .brainError 503 sops_unavailable",
          .disabled(if: BrainEnv.noSOPsURL.isEmpty, "Set ODX_PROXY_NOSOPS_URL"))
    func sopsUnavailable() async throws {
        BrainEnv.configure(BrainEnv.noSOPsURL)
        do {
            _ = try await OdxBrain.resolveSOP(query: "record a vendor bill")
            Issue.record("expected .brainError")
        } catch let e as OdxProxyError {
            guard case .brainError = e else { Issue.record("got \(e)"); return }
            #expect(e.brainStatus == 503)
            #expect(e.brainErrorType == "sops_unavailable")
        }
    }

    @Test("brainFacts agree between v1 and v2",
          .disabled(if: BrainEnv.odooURL.isEmpty, "Set ODOO_URL"))
    func facts() async throws {
        BrainEnv.configure(BrainEnv.proxyURL)
        let v2 = try await OdxApiV2.brainFacts(url: BrainEnv.odooURL)
        // Different URL spelling so v1 doesn't hit v2's cache entry.
        let v1 = try await OdxApi.brainFacts(url: BrainEnv.odooURL + "/")
        #expect(v2.odooVersion != nil)
        #expect(v2.edition != nil)
        #expect(v1 == v2)
    }
}
