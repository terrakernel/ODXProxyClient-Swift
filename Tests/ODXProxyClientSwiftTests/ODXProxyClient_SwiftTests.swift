//
//  ODXProxyClient_SwiftTests.swift
//
//  Integration tests against a live ODX proxy + Odoo instance.
//  Tests are skipped (not failed) when `TestCredentials.isConfigured` is false,
//  so the suite passes locally without credentials.
//
//  To run:
//    1. Fill in `TestCredentials.swift` in this directory.
//    2. swift test
//
//  All tests here are READ-ONLY against `res.partner`. They do not create,
//  update, or delete records.
//

import Testing
import Foundation

@testable import ODXProxyClientSwift

extension Tag {
    @Tag static var integration: Self
    @Tag static var network: Self
}

private struct Partner: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
}

private struct VersionInfo: Codable, Sendable {
    let serverVersion: String?

    enum CodingKeys: String, CodingKey {
        case serverVersion = "server_version"
    }
}

/// Configures the shared client. Cheap; configure() just rebuilds a
/// URLSession and stores a snapshot under a lock. Safe to call per test.
private func configureSharedClient() {
    let instance = OdxInstanceInfo(
        url: TestCredentials.odooURL,
        userId: TestCredentials.odooUserID,
        db: TestCredentials.odooDB,
        apiKey: TestCredentials.odooAPIKey
    )
    let clientInfo = OdxProxyClientInfo(
        instance: instance,
        odxApiKey: TestCredentials.odxAPIKey,
        gatewayUrl: TestCredentials.gatewayURL
    )
    OdxProxyClient.shared.configure(with: clientInfo, timeout: 30)
}

private func defaultKeyword(fields: [String]? = nil, limit: Int? = nil) -> OdxClientKeywordRequest {
    let context = OdxClientRequestContext(allowedCompanyIds: [1], defaultCompanyId: 1, tz: "UTC")
    return OdxClientKeywordRequest(fields: fields, limit: limit, context: context)
}

@Suite(
    "ODXProxy Integration",
    .tags(.integration, .network),
    .serialized,
    .disabled(if: !TestCredentials.isConfigured,
              "Fill in Tests/ODXProxyClientSwiftTests/TestCredentials.swift to enable integration tests.")
)
struct ODXProxyClientIntegrationTests {

    // MARK: - Data API

    @Test("searchRead res.partner returns at least one record")
    func searchRead_returnsRecords() async throws {
        configureSharedClient()

        let keyword = defaultKeyword(fields: ["id", "name"], limit: 5)
        let params = OdxParams([[]] as [[Any]])

        let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
            model: "res.partner",
            params: params,
            keyword: keyword
        )

        #expect(response.error == nil)
        let partners = try #require(response.result)
        #expect(!partners.isEmpty)
        if let first = partners.first {
            #expect(first.id > 0)
            #expect(!first.name.isEmpty)
        }
    }

    @Test("search res.partner returns ids only")
    func search_returnsIDs() async throws {
        configureSharedClient()

        let keyword = defaultKeyword(limit: 3)
        let params = OdxParams([[]] as [[Any]])

        let response = try await OdxApi.search(
            model: "res.partner",
            params: params,
            keyword: keyword
        )

        #expect(response.error == nil)
        let ids = try #require(response.result)
        #expect(ids.allSatisfy { $0 > 0 })
    }

    @Test("searchCount res.partner returns a non-negative count")
    func searchCount_returnsCount() async throws {
        configureSharedClient()

        let keyword = defaultKeyword()
        let params = OdxParams([[]] as [[Any]])

        let response = try await OdxApi.searchCount(
            model: "res.partner",
            params: params,
            keyword: keyword
        )

        #expect(response.error == nil)
        let count = try #require(response.result)
        #expect(count >= 0)
    }

    @Test("fieldsGet res.partner returns a non-empty schema")
    func fieldsGet_returnsSchema() async throws {
        configureSharedClient()

        let keyword = defaultKeyword()

        let response: OdxServerResponse<[String: AnyCodable]> = try await OdxApi.fieldsGet(
            model: "res.partner",
            keyword: keyword
        )

        #expect(response.error == nil)
        let schema = try #require(response.result)
        #expect(!schema.isEmpty)
        // 'name' is a field every Odoo install has on res.partner
        #expect(schema["name"] != nil)
    }

    @Test("read res.partner by id returns the same id back")
    func read_byID_returnsRecord() async throws {
        configureSharedClient()

        // First find an id via search
        let searchKeyword = defaultKeyword(limit: 1)
        let searchResponse = try await OdxApi.search(
            model: "res.partner",
            params: OdxParams([[]] as [[Any]]),
            keyword: searchKeyword
        )
        let ids = try #require(searchResponse.result)
        let firstID = try #require(ids.first)

        // Read it back
        let readKeyword = defaultKeyword(fields: ["id", "name"])
        let readResponse: OdxServerResponse<[Partner]> = try await OdxApi.read(
            model: "res.partner",
            params: OdxParams([[firstID]] as [[Any]]),
            keyword: readKeyword
        )

        #expect(readResponse.error == nil)
        let partners = try #require(readResponse.result)
        #expect(partners.count == 1)
        #expect(partners.first?.id == firstID)
    }

    // MARK: - Version endpoint

    @Test("version() against the configured Odoo URL returns a version_info")
    func version_returnsVersionInfo() async throws {
        configureSharedClient()

        let response: OdxServerResponse<VersionInfo> = try await OdxApi.version()

        #expect(response.error == nil)
        let info = try #require(response.result)
        // server_version is one of the keys Odoo ships in version_info.
        // It may be empty on some forks but should usually be present.
        #expect(info.serverVersion != nil)
    }

    // MARK: - Ops endpoints

    @Test("OdxOps.about returns a build identifier and version")
    func ops_about_returnsBuildInfo() async throws {
        configureSharedClient()

        let response = try await OdxOps.about()

        #expect(response.error == nil)
        let info = try #require(response.result)
        #expect(!info.build.isEmpty)
        #expect(!info.version.isEmpty)
    }

    @Test("OdxOps.license returns a license payload")
    func ops_license_returnsLicensePayload() async throws {
        configureSharedClient()

        let info = try await OdxOps.license()

        #expect(!info.licensee.isEmpty)
        #expect(!info.validUntil.isEmpty)
        // is_valid is a Bool; just exercising the decode.
        _ = info.isValid
    }

    // MARK: - Typed error mapping

    @Test("callMethod with empty fn_name throws missingFunctionName client-side")
    func callMethod_emptyFnName_throwsMissingFunctionName() async throws {
        configureSharedClient()

        let keyword = defaultKeyword()
        let params = OdxParams([[]] as [[Any]])

        await #expect(throws: OdxProxyError.self) {
            let _: OdxServerResponse<AnyCodable> = try await OdxApi.callMethod(
                model: "res.partner",
                functionName: "",
                params: params,
                keyword: keyword
            )
        }
    }
}
