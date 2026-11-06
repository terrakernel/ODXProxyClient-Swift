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
    /// v2 only (`OdxApiV2`): context merged into every v2 call; a call's own
    /// `context` keys win. Odoo applies no company selection unless
    /// `allowed_company_ids` is sent. Does not affect `OdxApi` (v1) calls.
    let defaultContext: OdxContext?
    
    enum CodingKeys: String, CodingKey {
        case instance, odxApiKey, gatewayUrl, defaultContext
    }
    
    public init(instance: OdxInstanceInfo, odxApiKey: String, gatewayUrl: String?, defaultContext: OdxContext? = nil) {
        self.instance = instance
        self.odxApiKey = odxApiKey
        self.gatewayUrl = gatewayUrl
        self.defaultContext = defaultContext
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

        // Per spec §6: result and error are mutually exclusive.
        // Decode error first; only decode result when no error is present, so
        // result-shape mismatches surface as errors instead of silent nils.
        error = try container.decodeIfPresent(OdxServerErrorResponse.self, forKey: .error)
        if error == nil {
            result = try container.decodeIfPresent(T.self, forKey: .result)
        } else {
            result = nil
        }
    }
    
    public init(jsonrpc: String, id: String, result: T?, error: OdxServerErrorResponse?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
    
}

public struct OdxServerErrorResponse: Codable, Error, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - Ops endpoints (SYSTEM_ARCHITECTURE.md §4.2–4.4)

/// Body shape for `POST /api/odoo/version`. The proxy queries the Odoo
/// server's public `/web/webclient/version_info` — no Odoo credentials needed.
public struct OdxVersionRequest: Encodable, Sendable {
    public let id: String
    public let url: String

    public init(id: String, url: String) {
        self.id = id
        self.url = url
    }
}

/// Response shape for `GET /_/about` (wrapped in `OdxServerResponse<OdxAboutInfo>`).
public struct OdxAboutInfo: Codable, Sendable {
    public let build: String
    public let version: String
    /// Optional sidecars the proxy is configured for, e.g. `["odxbrain": .bool(true)]`.
    /// Empty for proxies older than 0.10.0, which don't send `features`.
    public let features: [String: OdxParams]

    enum CodingKeys: String, CodingKey {
        case build, version, features
    }

    public init(build: String, version: String, features: [String: OdxParams] = [:]) {
        self.build = build
        self.version = version
        self.features = features
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        build = try container.decode(String.self, forKey: .build)
        version = try container.decode(String.self, forKey: .version)
        features = try container.decodeIfPresent([String: OdxParams].self, forKey: .features) ?? [:]
    }

    /// Whether `features[name]` is `true`. A missing key, or any non-`true` value,
    /// reads as `false`. `true` means the proxy is configured for the feature, not
    /// that the sidecar is up right now.
    public func hasFeature(_ name: String) -> Bool {
        if case .bool(true)? = features[name] { return true }
        return false
    }
}

/// Response shape for `GET /_/license` (flat object, NOT a JSON-RPC envelope).
public struct OdxLicenseInfo: Codable, Sendable {
    public let licensee: String
    public let validUntil: String
    public let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case licensee
        case validUntil = "valid_until"
        case isValid = "is_valid"
    }

    public init(licensee: String, validUntil: String, isValid: Bool) {
        self.licensee = licensee
        self.validUntil = validUntil
        self.isValid = isValid
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




/// Property wrapper for Odoo-style optional fields, which encode "unset" as
/// the literal Bool `false` instead of `null`.
///
/// Usage at a call site looks like a normal Swift `Optional`:
/// ```swift
/// struct Product: Codable, Sendable {
///     let id: Int
///     @OdxOptional var barcode: String?
/// }
///
/// let p = try JSONDecoder().decode(Product.self, from: json)
/// print(p.barcode ?? "no barcode")   // String? — no `.value` indirection
/// ```
///
/// ## Decoding rules
///
/// | JSON value | Decoded result      |
/// |------------|---------------------|
/// | `null`     | `nil`               |
/// | `false`    | `nil` (Odoo convention) |
/// | absent key | `nil` (safety net)  |
/// | a real `T` | `.some(value)`      |
/// | any other  | throws `DecodingError` |
///
/// ## Encoding rules
///
/// - `nil` encodes as JSON `false` (Odoo convention — symmetric with decode).
/// - `.some(value)` encodes as `value`.
///
/// ## Caveat: `@OdxOptional var x: Bool?`
///
/// For `Wrapped == Bool`, the wire `false` always decodes to `nil` — Odoo's
/// convention makes it impossible to distinguish "actually false" from "unset"
/// from the JSON alone. This is a wire-format limitation, not a library bug.
@propertyWrapper
public struct OdxOptional<Wrapped: Codable & Sendable>: Codable, Sendable {
    public var wrappedValue: Wrapped?

    public init(wrappedValue: Wrapped?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.wrappedValue = nil
            return
        }

        // Odoo's "unset" convention: literal Bool false means no value.
        // Note: when Wrapped is Bool itself, we cannot distinguish "false"
        // from "unset" — see the type's caveat doc.
        if let bool = try? container.decode(Bool.self), bool == false {
            self.wrappedValue = nil
            return
        }

        self.wrappedValue = try container.decode(Wrapped.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(value)
        } else {
            try container.encode(false)
        }
    }
}

/// Makes `@OdxOptional` decode missing JSON keys as `nil` instead of throwing,
/// mirroring the behavior callers expect from `Optional` properties.
extension KeyedDecodingContainer {
    public func decode<Wrapped>(
        _ type: OdxOptional<Wrapped>.Type,
        forKey key: Key
    ) throws -> OdxOptional<Wrapped> {
        try decodeIfPresent(type, forKey: key) ?? OdxOptional(wrappedValue: nil)
    }
}


// MARK: - v2 (Odoo JSON-2, ODXProxy 0.9.0+)

/// Odoo context for `OdxApiV2` calls, sent as `kwargs.context`.
///
/// Common keys have labelled parameters; anything else goes in `extra`, keyed by
/// Odoo's own context key (never case-converted).
///
/// ```swift
/// let ctx = OdxContext(lang: "en_US", tz: "Asia/Jakarta", allowedCompanyIds: [1])
/// ```
public struct OdxContext: Codable, Sendable {
    public var values: [String: OdxParams]

    public init(lang: String? = nil, tz: String? = nil, allowedCompanyIds: [Int]? = nil, extra: [String: OdxParams] = [:]) {
        var values = extra
        if let lang { values["lang"] = .string(lang) }
        if let tz { values["tz"] = .string(tz) }
        if let allowedCompanyIds { values["allowed_company_ids"] = .array(allowedCompanyIds.map { .number(Double($0)) }) }
        self.values = values
    }

    public init(_ values: [String: OdxParams]) {
        self.values = values
    }

    /// Returns `self` overlaid with `other`; keys from `other` win.
    public func merging(_ other: OdxContext?) -> OdxContext {
        guard let other else { return self }
        return OdxContext(values.merging(other.values) { _, new in new })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: OdxParams].self)
    }
}

/// Result of `OdxApiV2.version`: Odoo's `GET /json/version`, which has a
/// different shape from the v1 `OdxApi.version` result.
public struct OdxV2VersionInfo: Codable, Sendable {
    /// e.g. `[20, 0, 0, "final", 0, "e"]`
    public let versionInfo: [OdxParams]
    /// e.g. `"20.0+e"`
    public let version: String

    enum CodingKeys: String, CodingKey {
        case versionInfo = "version_info"
        case version
    }

    public init(versionInfo: [OdxParams], version: String) {
        self.versionInfo = versionInfo
        self.version = version
    }

    /// Odoo's major version (`versionInfo[0]`), e.g. `20`.
    public var major: Int? {
        if case .number(let n)? = versionInfo.first { return Int(n) }
        return nil
    }
}

/// `odoo_instance` for v2. There is no `user_id`, because JSON-2 derives the user
/// from the API key.
struct OdxV2Instance: Encodable, Sendable {
    let url: String
    let db: String
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case url, db
        case apiKey = "api_key"
    }
}

/// Named arguments for a JSON-2 call, encoded as one JSON object. Keys are Odoo's
/// Python parameter names verbatim (`domain`, `fields`, `vals_list`, `ids`, ...).
/// `set` drops `nil`, so an argument the caller didn't pass is omitted and Odoo's
/// own default applies.
struct OdxV2Kwargs: Encodable, Sendable {
    private(set) var entries: [String: any Encodable & Sendable] = [:]

    mutating func set(_ key: String, _ value: (any Encodable & Sendable)?) {
        if let value { entries[key] = value }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in entries {
            try container.encode(value, forKey: Key(key))
        }
    }
}

/// Body of `POST /v2/odoo/execute` (SYSTEM_ARCHITECTURE §4.6).
struct OdxV2Request: Encodable, Sendable {
    let id: String
    let modelId: String
    let method: String
    let kwargs: OdxV2Kwargs
    let odooInstance: OdxV2Instance

    enum CodingKeys: String, CodingKey {
        case id, method, kwargs
        case modelId = "model_id"
        case odooInstance = "odoo_instance"
    }
}


// MARK: - ODXBrain (ODXProxy 0.10.0+, SYSTEM_ARCHITECTURE.md §4.8–§4.10, §7.2)

/// Odoo edition, as ODXBrain filters by it.
public enum OdxBrainEdition: String, Codable, Sendable {
    case community
    case enterprise
}

/// The facts about an Odoo instance that ODXBrain filters by. A `nil` fact is
/// omitted from the request, which filters nothing; never guess one, because a
/// wrong version silently removes correct answers.
public struct OdxBrainFacts: Codable, Sendable, Equatable {
    /// Odoo's serie, e.g. `"20.0"` or `"saas~16.3"`.
    public var odooVersion: String?
    public var edition: OdxBrainEdition?

    enum CodingKeys: String, CodingKey {
        case odooVersion = "odoo_version"
        case edition
    }

    public init(odooVersion: String? = nil, edition: OdxBrainEdition? = nil) {
        self.odooVersion = odooVersion
        self.edition = edition
    }

    /// From a v1 `/api/odoo/version` result: `server_serie`, and enterprise iff
    /// `server_version` contains `"+e"`.
    static func fromV1(_ result: [String: OdxParams]) -> OdxBrainFacts {
        var facts = OdxBrainFacts()
        if case .string(let serie)? = result["server_serie"], !serie.isEmpty {
            facts.odooVersion = serie
        }
        if case .string(let version)? = result["server_version"] {
            facts.edition = edition(of: version)
        }
        return facts
    }

    /// From a v2 `/v2/odoo/version` result: the first two `version_info` entries
    /// joined by `"."`, and enterprise iff `version` contains `"+e"`.
    static func fromV2(_ result: OdxV2VersionInfo) -> OdxBrainFacts {
        var facts = OdxBrainFacts()
        let parts = result.versionInfo.prefix(2).compactMap { part -> String? in
            switch part {
            case .number(let n) where n == n.rounded(): return String(Int(n))
            case .number(let n): return String(n)
            case .string(let s): return s
            default: return nil
            }
        }
        if parts.count == 2 {
            facts.odooVersion = parts.joined(separator: ".")
        }
        facts.edition = edition(of: result.version)
        return facts
    }

    /// Packaged builds report `"20.0+e-20260925"` and pre-releases `"20.0alpha1+e"`,
    /// so look for `"+e"` rather than cutting at `"+"`.
    private static func edition(of version: String) -> OdxBrainEdition? {
        guard !version.isEmpty else { return nil }
        return version.contains("+e") ? .enterprise : .community
    }
}

/// Token usage ODXBrain reports for a query.
public struct OdxBrainUsage: Codable, Sendable {
    public let promptTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
    }
}

/// Result of `OdxBrain.resolveModel`: ranked Odoo models for a question.
///
/// `candidates` is every candidate ODXBrain returned, in its order. Ordering is the
/// contract; the score scale is not, so don't threshold on `score`. Fields this
/// type doesn't model are kept in `raw`, which is also what encoding writes back.
public struct OdxBrainModelResolution: Codable, Sendable {
    public struct Candidate: Codable, Sendable {
        /// Odoo model name, e.g. `"account.move"`.
        public let model: String
        public let score: Double
        /// The model's availability on that version/edition rests on inference,
        /// not audited source. `false` when ODXBrain omits it.
        public let provisional: Bool

        enum CodingKeys: String, CodingKey {
            case model, score, provisional
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = try c.decode(String.self, forKey: .model)
            score = try c.decode(Double.self, forKey: .score)
            provisional = try c.decodeIfPresent(Bool.self, forKey: .provisional) ?? false
        }
    }

    /// A model that would have ranked but doesn't exist on that Odoo version or edition.
    public struct Exclusion: Codable, Sendable {
        public let model: String
        public let reason: String
        public let successor: String?
    }

    public let candidates: [Candidate]
    /// The embedding model (wire key `model`), e.g. `"bge-m3"`. Watch it, `dim` and
    /// `corpusVersion`: a swap changes answers without erroring anywhere.
    public let embeddingModel: String
    public let dim: Int
    public let corpusVersion: String
    public let usage: OdxBrainUsage?
    /// Empty when ODXBrain sends no `excluded`.
    public let excluded: [Exclusion]
    /// `false` when neither `odoo_version` nor `edition` was sent; `nil` when absent.
    public let filtered: Bool?
    /// Set when the `odoo_version` sent is newer than the audited range. Its value
    /// is the newest audited version (e.g. `"19.0"` for a 20.0 query), not the
    /// version that was sent.
    public let versionUnaudited: String?
    /// The whole `result` object as ODXBrain sent it, including fields this type
    /// doesn't model yet.
    public let raw: OdxParams

    enum CodingKeys: String, CodingKey {
        case candidates, dim, usage, excluded, filtered
        case embeddingModel = "model"
        case corpusVersion = "corpus_version"
        case versionUnaudited = "version_unaudited"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try c.decode([Candidate].self, forKey: .candidates)
        embeddingModel = try c.decode(String.self, forKey: .embeddingModel)
        dim = try c.decode(Int.self, forKey: .dim)
        corpusVersion = try c.decode(String.self, forKey: .corpusVersion)
        usage = try c.decodeIfPresent(OdxBrainUsage.self, forKey: .usage)
        excluded = try c.decodeIfPresent([Exclusion].self, forKey: .excluded) ?? []
        filtered = try c.decodeIfPresent(Bool.self, forKey: .filtered)
        versionUnaudited = try c.decodeIfPresent(String.self, forKey: .versionUnaudited)
        raw = try OdxParams(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}

/// Result of `OdxBrain.resolveSOP`: ranked SOPs for a task.
///
/// `match == "none"` means no SOP is a confident match: stop and ask, don't run the
/// nearest procedure. Embeddings match the topic, not the operation, so check the
/// chosen candidate's `title` against the task before acting. The SOP body comes
/// from the doc manager (`odxdocs`), not from the proxy. Unmodelled fields are
/// kept in `raw`.
public struct OdxBrainSOPResolution: Codable, Sendable {
    public struct Candidate: Codable, Sendable {
        public let id: String
        public let version: String
        public let title: String
        public let score: Double
    }

    /// A SOP filtered out on this instance, e.g. `reason: "needs module sale"`.
    public struct Exclusion: Codable, Sendable {
        public let id: String
        public let reason: String
    }

    /// The approved SOP set the answer came from. Record `root` with any action
    /// taken, to tie it to that set.
    public struct SOPSet: Codable, Sendable {
        public let generation: Int
        /// 64 hex characters.
        public let root: String
    }

    public let candidates: [Candidate]
    /// The embedding model (wire key `model`), e.g. `"bge-m3"`.
    public let embeddingModel: String
    public let dim: Int
    public let sops: SOPSet
    /// `"none"` when no SOP is a confident match; `nil` when absent.
    public let match: String?
    /// Empty when ODXBrain sends no `excluded`.
    public let excluded: [Exclusion]
    /// Facts the caller didn't send, e.g. `["odoo_version", "company"]`. Empty when absent.
    public let factsMissing: [String]
    public let usage: OdxBrainUsage?
    /// The whole `result` object as ODXBrain sent it.
    public let raw: OdxParams

    enum CodingKeys: String, CodingKey {
        case candidates, dim, sops, match, excluded, usage
        case embeddingModel = "model"
        case factsMissing = "facts_missing"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try c.decode([Candidate].self, forKey: .candidates)
        embeddingModel = try c.decode(String.self, forKey: .embeddingModel)
        dim = try c.decode(Int.self, forKey: .dim)
        sops = try c.decode(SOPSet.self, forKey: .sops)
        match = try c.decodeIfPresent(String.self, forKey: .match)
        excluded = try c.decodeIfPresent([Exclusion].self, forKey: .excluded) ?? []
        factsMissing = try c.decodeIfPresent([String].self, forKey: .factsMissing) ?? []
        usage = try c.decodeIfPresent(OdxBrainUsage.self, forKey: .usage)
        raw = try OdxParams(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try raw.encode(to: encoder)
    }
}

/// Body of `POST /brain/v1/resolve` and `/brain/v1/sops/resolve`: `id` plus the
/// fields that were set, flat. `nil` fields are omitted, never sent as `null`.
struct OdxBrainRequest: Encodable, Sendable {
    let id: String
    let fields: OdxV2Kwargs

    func encode(to encoder: Encoder) throws {
        var fields = fields
        fields.set("id", id)
        try fields.encode(to: encoder)
    }
}
