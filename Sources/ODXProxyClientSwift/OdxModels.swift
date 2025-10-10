import Foundation

// MARK: - Configuration Structures

public struct OdxInstanceInfo: Codable {
    let url: String
    let userId: Int
    let db: String
    let apiKey: String
    
    enum CodingKeys: String, CodingKey {
        case url,db
        case userId = "user_id"
        case apiKey = "api_key"
    }
}

public struct OdxProxyClientInfo: Codable {
    let instance: OdxInstanceInfo
    let odxApiKey: String
    let gatewayUrl: String?

}

// MARK: - Request Structures

public struct OdxClientRequestContext: Codable {
    var allowedCompanyIds: [Int]?
    var defaultCompanyId: Int?
    var tz: String
    
    enum CodingKeys: String, CodingKey {
        case tz
        case allowedCompanyIds = "allowed_company_ids"
        case defaultCompanyId = "default_company_id"
    }
}

public struct OdxClientKeywordRequest: Codable {
    var fields: [String]?
    var order: String?
    var limit: Int?
    var offset: Int?
    var context: OdxClientRequestContext
}

public struct OdxClientRequest: Encodable {
    let id: String
    let action: String
    let modelId: String
    var keyword: OdxClientKeywordRequest
    var fnName: String?
    let params: [AnyEncodable]
    let odooInstance: OdxInstanceInfo

    enum CodingKeys: String, CodingKey {
        case id, action, keyword, params
        case modelId = "model_id"
        case fnName = "fn_name"
        case odooInstance = "odoo_instance"
    }
}


// MARK: - Response Structures

public struct OdxServerResponse<T: Codable>: Codable {
    let jsonrpc: String
    let id: String
    let result: T?
    let error: OdxServerErrorResponse?
}

public struct OdxServerErrorResponse: Codable, Error {
    let code: Int
    let message: String
    let data: AnyCodable?
}
