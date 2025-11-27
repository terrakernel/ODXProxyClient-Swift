import Foundation

// MARK: - Configuration Structures
public struct OdxInstanceInfo: Codable, Sendable {
    let url: String
    let userId: Int
    let db: String
    let apiKey: String
    
    enum CodingKeys: String, CodingKey {
        case url,db
        case userId = "user_id"
        case apiKey = "api_key"
    }
    
    public init(url: String, userId: Int, db: String, apiKey: String) {
        self.url = url
        self.userId = userId
        self.db = db
        self.apiKey = apiKey
    }
}

public struct OdxProxyClientInfo: Codable, Sendable {
    let instance: OdxInstanceInfo
    let odxApiKey: String
    let gatewayUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case instance, odxApiKey, gatewayUrl
    }
    
    public init(instance: OdxInstanceInfo, odxApiKey: String, gatewayUrl: String?) {
        self.instance = instance
        self.odxApiKey = odxApiKey
        self.gatewayUrl = gatewayUrl
    }

}

// MARK: - Request Structures
public struct OdxClientRequestContext: Codable, Sendable {
    var allowedCompanyIds: [Int]?
    var defaultCompanyId: Int?
    var tz: String
    
    enum CodingKeys: String, CodingKey {
        case tz
        case allowedCompanyIds = "allowed_company_ids"
        case defaultCompanyId = "default_company_id"
    }
    
    public init(allowedCompanyIds: [Int]? = nil, defaultCompanyId: Int? = nil, tz: String) {
        self.allowedCompanyIds = allowedCompanyIds
        self.defaultCompanyId = defaultCompanyId
        self.tz = tz
    }
}

public struct OdxClientKeywordRequest: Codable, Sendable {
    var fields: [String]?
    var order: String?
    var limit: Int?
    var offset: Int?
    var context: OdxClientRequestContext
    
    public init(fields: [String]? = nil, order: String? = nil, limit: Int? = nil, offset: Int? = nil, context: OdxClientRequestContext) {
        self.fields = fields
        self.order = order
        self.limit = limit
        self.offset = offset
        self.context = context
    }
}

public struct OdxClientRequest: Encodable, Sendable {
    let id: String
    let action: String
    let modelId: String
    var keyword: OdxClientKeywordRequest
    var fnName: String?
    let params: OdxParams
    let odooInstance: OdxInstanceInfo

    enum CodingKeys: String, CodingKey {
        case id, action, keyword, params
        case modelId = "model_id"
        case fnName = "fn_name"
        case odooInstance = "odoo_instance"
    }
    
    public init(id: String, action: String, modelId: String, keyword: OdxClientKeywordRequest, fnName: String? = nil, params: OdxParams, odooInstance: OdxInstanceInfo) {
        self.id = id
        self.action = action
        self.modelId = modelId
        self.keyword = keyword
        self.fnName = fnName
        self.params = params
        self.odooInstance = odooInstance
    }
}


/// A flexible, type-erased JSON value container used for constructing
/// Odoo RPC parameters (`params[]`) in a strongly-typed but dynamic way.
///
/// `OdxParams` can represent any valid JSON value, including:
///
/// - `.string(String)`
/// - `.number(Double)`
/// - `.bool(Bool)`
/// - `.null`
/// - `.array([OdxParams])`
/// - `.object([String: OdxParams])`
///
/// It is designed to safely bridge between Swift type-checking and Odoo’s
/// highly dynamic JSON structures.
///
/// ## Why This Exists
/// Odoo does not use traditional REST JSON schemas. Instead, payloads such as:
///
/// ```json
/// [
///   "product.template",
///   [ [ "name", "=", "Apple" ] ],
///   { "limit": 80 }
/// ]
/// ```
///
/// may contain nested arrays, mixed types, or arbitrary key/value objects.
///
/// `OdxParams` provides:
///
/// - A type-safe representation for Swift
/// - Codable interoperability
/// - Ability to initialize from `Any` safely
/// - Sendable conformance for async/await background encoding/decoding
///
///
/// ## Dynamic Initialization
/// You can construct `OdxParams` from any common Swift JSON type:
///
/// ```swift
/// OdxParams("hello")                              // .string
/// OdxParams(123)                                  // .number
/// OdxParams(["name": "Apple", "qty": 25])         // .object
/// OdxParams([1, "x", true, NSNull()])             // .array
/// ```
///
/// Unsupported values automatically fall back to `.null`.
///
///
/// ## Codable Behavior
/// - Encoding uses a `singleValueContainer`, letting OdxParams behave exactly
///   like normal JSON when serialized.
/// - Decoding attempts each JSON type in order:
///   `nil → String → Double → Bool → [OdxParams] → [String: OdxParams]`
/// - If none match, decoding throws a `dataCorrupted` error.
///
///
/// ## Example Usage in Odoo RPC
/// ```swift
/// let params = OdxParams([
///     [
///         ["name": "Product A", "list_price": 10.5],
///         ["name": "Product B", "list_price": 12.0]
///     ]
/// ])
///
/// try await OdxApi.create(
///     model: "product.template",
///     params: params,
///     keyword: keyword
/// )
/// ```
///
/// This allows flexible request building without losing Swift type-safety.
///
///
/// ## Concurrency
/// `OdxParams` conforms to `Sendable`, allowing it to safely cross actor
/// boundaries, and making it compatible with:
///
/// - `Task.detached`
/// - background JSON encoding/decoding
/// - Swift strict concurrency mode
///
///
/// A dynamic JSON parameter tree used for writing and sending Odoo RPC requests.
public enum OdxParams: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([OdxParams])
    case object([String: OdxParams])

    public init(_ value: Any) {
        switch value {
        case let v as String: self = .string(v)
        case let v as Int: self = .number(Double(v))
        case let v as Double: self = .number(v)
        case let v as Bool: self = .bool(v)
        case is NSNull: self = .null

        case let v as [Any]:
            self = .array(v.map { OdxParams($0) })

        case let v as [String: Any]:
            self = .object(v.mapValues { OdxParams($0) })

        default:
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x): try container.encode(x)
        case .number(let x): try container.encode(x)
        case .bool(let x):   try container.encode(x)
        case .null:          try container.encodeNil()

        case .array(let arr):
            try container.encode(arr)

        case .object(let obj):
            try container.encode(obj)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode([OdxParams].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode([String: OdxParams].self) {
            self = .object(value)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON type"
        )
    }
}

//MARK: - Server Responses

public struct OdxServerResponse<T: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let result: T?
    public let error: OdxServerErrorResponse?
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

            jsonrpc = try container.decode(String.self, forKey: .jsonrpc)

            if let idInt = try? container.decode(Int.self, forKey: .id) {
                id = String(idInt)
            } else if let idStr = try? container.decode(String.self, forKey: .id) {
                id = idStr
            } else {
                id = ""
            }

            result = try? container.decode(T.self, forKey: .result)
            error  = try? container.decode(OdxServerErrorResponse.self, forKey: .error)
    }
    
    public init(jsonrpc: String, id: String, result: T?, error: OdxServerErrorResponse?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
    
}

public struct OdxServerErrorResponse: Codable, Error, Sendable {
    let code: Int
    let message: String
    let data: AnyCodable?
    
    public init(code: Int, message: String, data: AnyCodable?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

//MARK: - Odoo Field Helper

/// A representation of an Odoo Many2One relational field, which is commonly
/// returned as either:
///
/// - `false` / `null` (meaning no relation), or
/// - a two-element array: `[id, name]`
///
/// This struct normalizes Odoo’s flexible Many2One encoding into a strongly-typed
/// Swift object with optional `id` and `name` properties.
///
/// ## Supported JSON Formats
///
/// ### 1. Many2One is not set
/// ```json
/// "partner_id": false
/// ```
/// or
/// ```json
/// "partner_id": null
/// ```
///
/// → Decodes to:
/// ```swift
/// OdxMany2One(id: nil, name: nil)
/// ```
///
/// ### 2. Many2One contains a linked record
/// ```json
/// "partner_id": [42, "Acme Corp"]
/// ```
///
/// → Decodes to:
/// ```swift
/// OdxMany2One(id: 42, name: "Acme Corp")
/// ```
///
/// ## Behavior Summary
/// - If the JSON value is `false`, `null`, or an empty array → both fields become `nil`.
/// - If the JSON value is an array, decoding attempts `Int` for index 0 and `String` for index 1.
/// - Encoding follows Odoo’s conventions:
///   - If `id == nil` → encodes as `null`.
///   - Otherwise → encodes as `[id, name]`.
///
/// ## Example Usage
/// ```swift
/// struct Product: Codable {
///     let product_tmpl_id: OdxMany2One
/// }
///
/// let json = #"{"product_tmpl_id": [10, "Template Name"]}"#.data(using: .utf8)!
/// let decoded = try JSONDecoder().decode(Product.self, from: json)
/// print(decoded.product_tmpl_id.id)   // Optional(10)
/// print(decoded.product_tmpl_id.name) // Optional("Template Name")
/// ```
///
/// ## Concurrency
/// This type conforms to `Sendable`, making it safe to cross concurrency boundaries
/// (e.g., decoding on a background thread using `Task.detached`).
///
/// ## Encoding/Decoding Notes
/// - This implementation uses an unkeyed container because Odoo uses array encoding.
/// - Decoding uses `try?` for each element to avoid throwing for partially-formed arrays.
/// - This matches Odoo's real-world behavior, which can be inconsistent in field formats.
///
///
/// - Important:
///   Although Odoo *should* always send `[id, name]`, in practice the name field is
///   sometimes `false` or missing; this implementation handles those cases safely.
///
///
/// A Many2One linking structure used by Odoo JSON responses.
///
/// - Parameters:
///   - id: The integer ID of the related record.
///   - name: The display name of the related record.
public struct OdxMany2One: Codable, Sendable {
    public let id: Int?
    public let name: String?

    public init(id: Int?, name: String?) {
        self.id = id
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        if container.isAtEnd {
            self.id = nil
            self.name = nil
            return
        }

        // CASE 1: many2one = false or null
        if let isNil = try? container.decodeNil(), isNil {
            self.id = nil
            self.name = nil
            return
        }

        // CASE 2: [id, name]
        let id = try? container.decode(Int.self)
        let name = try? container.decode(String.self)

        self.id = id
        self.name = name
    }

    public func encode(to encoder: Encoder) throws {
        if id == nil {
            var container = encoder.singleValueContainer()
            try container.encodeNil()   // encode as null
            return
        }

        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(name)
    }
}




/// A wrapper type used to decode Odoo-style optional values where `false`, `null`,
/// or a missing field all represent the absence of a value.
///
/// `OptionalOdxValue` is designed specifically for Odoo JSON responses, where optional
/// fields are often encoded unpredictably:
/// - `null` → means no value
/// - `false` → *also* means no value (common for unset Many2One or empty fields)
/// - A real value of type `T`
///
/// This type normalizes all those cases into a single `value: T?`, making decoding logic
/// much cleaner and preventing type mismatches during JSON parsing.
///
/// ## Example JSON Inputs
///
/// | JSON Value | Meaning | Decoded Result |
/// |------------|---------|----------------|
/// | `null`     | No value | `value == nil` |
/// | `false`    | No value | `value == nil` |
/// | `"ABC"`    | Valid `T` | `.some("ABC")` |
/// | `123`      | Valid `T` | `.some(123)` |
///
/// ## Example Usage
/// ```swift
/// struct Product: Codable, Sendable {
///     let barcode: OptionalOdxValue<String>
/// }
///
/// let json = #"{"barcode": false}"#.data(using: .utf8)!
/// let p = try JSONDecoder().decode(Product.self, from: json)
/// print(p.barcode.value) // nil
/// ```
///
/// - Note:
/// This type is `Sendable` so it is safe to use across Swift concurrency
/// boundaries (e.g., decoding in background threads).
///
/// - Warning:
/// If the JSON contains an invalid type for `T` that cannot be decoded, the value
/// will silently become `nil` (`decode(T.self)` is attempted with `try?`).
///
/// - Type Parameter:
///   - `T`: The underlying value type, which must conform to `Codable` and `Sendable`.
public struct OptionalOdxValue<T: Codable & Sendable>: Codable, Sendable {
    public let value: T?
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = nil
            return
        }
        
        if let boolVal = try? container.decode(Bool.self) {
            if boolVal == false {
                self.value = nil
                return
            }
        }
        
        self.value = try? container.decode(T.self)
    }
    
}

