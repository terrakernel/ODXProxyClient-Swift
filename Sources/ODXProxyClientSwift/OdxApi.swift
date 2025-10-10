import Foundation

@MainActor
public enum OdxApi {
    private static func client() -> OdxProxyClient {
        return OdxProxyClient.shared
    }

    public static func search<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<[T]> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }

        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "search",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )

        return try await client().postRequest(body: body)
    }
    
    public static func searchRead<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<[T]> {
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }
        
        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "search_read",
            modelId: model,
            keyword: keyword,
            params: params,
            odooInstance: odooInstance
        )

        return try await client().postRequest(body: body)
    }

    public static func read<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil

        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }
        
        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "read",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )

        return try await client().postRequest(body: body)
    }

    public static func fieldsGet<T: Codable>(model: String, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil

        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }

        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "fields_get",
            modelId: model,
            keyword: kCopy,
            params: [],
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }

    public static func searchCount(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<Int> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }
        
        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "search_count",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }

    public static func create<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }
        
        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "create",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }

    public static func remove<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }

        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "unlink",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )

        return try await client().postRequest(body: body)
    }
    
    public static func write<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }
        
        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "write",
            modelId: model,
            keyword: kCopy,
            params: params,
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }

    public static func update<T: Codable>(model: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        return try await write(model: model, params: params, keyword: keyword, id: id)
    }

    public static func callMethod<T: Codable>(model: String, functionName: String, params: [AnyEncodable], keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        var kCopy = keyword
        kCopy.order = nil
        kCopy.limit = nil
        kCopy.offset = nil
        kCopy.fields = nil
        
        guard let odooInstance = client().getOdooInstance() else {
            throw OdxProxyError.notConfigured
        }

        let body = OdxClientRequest(
            id: id ?? ULID().ulidString,
            action: "call_method",
            modelId: model,
            keyword: kCopy,
            fnName: functionName,
            params: params,
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }
}
