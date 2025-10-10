//
//  ODXProxyClient_SwiftTests.swift
//  ODXProxyClient-SwiftTests
//
//  Created by Julian Richie on 08/10/25.
//

import Testing
import Foundation

@testable import ODXProxyClient_Swift


private struct Partner: Codable, Identifiable {
    let id: Int
    let name: String
    let write_uid: [AnyCodable]
}

struct ODXProxyClientIntegrationTests {

    @Test("Search Read - Live API Call", .tags(.integration, .network))
    func searchRead_withValidCredentials_shouldSucceed() async throws {
        
        let gatewayURL = try #require(ProcessInfo.processInfo.environment["ODX_GATEWAY_URL"])
        let odxAPIKey = try #require(ProcessInfo.processInfo.environment["ODX_API_KEY"])
        let odooURL = try #require(ProcessInfo.processInfo.environment["ODOO_URL"])
        let odooDB = try #require(ProcessInfo.processInfo.environment["ODOO_DB"])
        let odooUserIDString = try #require(ProcessInfo.processInfo.environment["ODOO_USER_ID"])
        let odooUserID = try #require(Int(odooUserIDString))
        let odooAPIKey = try #require(ProcessInfo.processInfo.environment["ODOO_API_KEY"])
        
        let odooInstance = OdxInstanceInfo(url: odooURL, userId: odooUserID, db: odooDB, apiKey: odooAPIKey)
        let clientInfo = OdxProxyClientInfo(instance: odooInstance, odxApiKey: odxAPIKey, gatewayUrl: gatewayURL)
        await OdxProxyClient.shared.configure(with: clientInfo, timeout: 60)
        
        let context = OdxClientRequestContext(allowedCompanyIds: [1], defaultCompanyId: 1, tz: "UTC")
        let keyword = OdxClientKeywordRequest(fields: ["id", "name","write_uid"], limit: 1, context: context)
        
        
        // 4. Perform the API call.
        let searchDomain: [Any] = [
            ["name","ilike","acme"]
        ]
        let params: [AnyEncodable] = [AnyEncodable(searchDomain)]
        let response: OdxServerResponse<[Partner]> = try await OdxApi.searchRead(
            model: "res.partner",
            params: params,
            keyword: keyword
        )

        #expect(response.error == nil)
        
        let partners = try #require(response.result) // #require unwraps the optional
        
        #expect(partners.count >= 1)
        
        if let firstPartner = partners.first {
            #expect(firstPartner.id > 0)
            #expect(!firstPartner.name.isEmpty)
        }
    }
}

// Add a custom Tag for better organization
extension Tag {
    @Tag static var integration: Self
    @Tag static var network: Self
}
