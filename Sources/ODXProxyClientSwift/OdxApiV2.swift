import Foundation

/// The v2 data API: ODXProxy `/v2/odoo/*` (ODXProxy 0.9.0+), which reaches Odoo
/// over its JSON-2 API instead of `/jsonrpc`. Needs **Odoo 19+**. Odoo 22 removes
/// `/jsonrpc`, so from then on v2 is the only way in.
///
/// It uses the same `OdxProxyClient.shared.configure(with:)` as `OdxApi`. The
/// instance's `userId` is not sent, because JSON-2 derives the user from the API key,
/// which must be an Odoo **API key**, not a password.
///
/// Differences from `OdxApi` (v1):
/// - **Named arguments only.** Each method sends its arguments under Odoo's Python
///   parameter names (`domain`, `fields`, `vals_list`, `ids`, ...). There are no
///   positional `params` and no `keyword`. `domain` is the domain list itself, e.g.
///   `OdxParams([["is_company", "=", true]])`, without v1's extra wrapping array.
/// - Arguments left `nil` are omitted, so Odoo's own defaults apply.
/// - `create` always returns `[Int]`; use `createOne` for a single id.
/// - Odoo errors arrive as `OdxProxyError.odooLogic`, and `odooStatus` holds Odoo's
///   HTTP status (e.g. 422). `-32006` is `.json2Unavailable` and `-32007` is
///   `.invalidRequest`.
///
/// ```swift
/// let partners: OdxServerResponse<[Partner]> = try await OdxApiV2.searchRead(
///     model: "res.partner",
///     domain: OdxParams([["is_company", "=", true]]),
///     fields: ["name"],
///     limit: 20
/// )
/// ```
public enum OdxApiV2 {

    private static func client() -> OdxProxyClient {
        OdxProxyClient.shared
    }

    // MARK: - Request building

    /// Builds the wire request. Pure: the instance and default context are passed
    /// in, so unit tests can check the exact JSON without configuring the client.
    /// The call's `context` is merged over the default context (call keys win), and
    /// `context` is omitted when both are empty.
    static func makeRequest(
        model: String,
        method: String,
        kwargs: OdxV2Kwargs,
        context: OdxContext?,
        instance: OdxInstanceInfo,
        defaultContext: OdxContext?,
        id: String?
    ) -> OdxV2Request {
        var kwargs = kwargs
        let merged = (defaultContext ?? OdxContext([:])).merging(context)
        if !merged.values.isEmpty {
            kwargs.set("context", merged)
        }
        return OdxV2Request(
            id: id ?? ULID().ulidString,
            modelId: model,
            method: method,
            kwargs: kwargs,
            odooInstance: OdxV2Instance(url: instance.url, db: instance.db, apiKey: instance.apiKey)
        )
    }

    private static func execute<T: Codable & Sendable>(
        _ call: OdxV2Call,
        model: String,
        context: OdxContext?,
        id: String?
    ) async throws -> OdxServerResponse<T> {
        guard let binding = client().getV2Binding() else {
            throw OdxProxyError.notConfigured
        }
        let body = makeRequest(
            model: model,
            method: call.method,
            kwargs: call.kwargs,
            context: context,
            instance: binding.instance,
            defaultContext: binding.defaultContext,
            id: id
        )
        return try await client().postV2ExecuteRPC(body: body)
    }

    // MARK: - Data API

    /// Searches `model` and returns the matching record ids.
    ///
    /// ```swift
    /// let ids = try await OdxApiV2.search(model: "res.partner", domain: OdxParams([["customer_rank", ">", 0]]), limit: 10)
    /// ```
    public static func search(
        model: String,
        domain: OdxParams,
        offset: Int? = nil,
        limit: Int? = nil,
        order: String? = nil,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<[Int]> {
        try await execute(.search(domain: domain, offset: offset, limit: limit, order: order), model: model, context: context, id: id)
    }

    /// Searches `model` and reads the matching records into `T`. With no `domain`,
    /// every record matches.
    public static func searchRead<T: Codable & Sendable>(
        model: String,
        domain: OdxParams? = nil,
        fields: [String]? = nil,
        offset: Int? = nil,
        limit: Int? = nil,
        order: String? = nil,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<[T]> {
        try await execute(.searchRead(domain: domain, fields: fields, offset: offset, limit: limit, order: order), model: model, context: context, id: id)
    }

    /// Counts the records of `model` that match `domain`.
    public static func searchCount(
        model: String,
        domain: OdxParams,
        limit: Int? = nil,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<Int> {
        try await execute(.searchCount(domain: domain, limit: limit), model: model, context: context, id: id)
    }

    /// Reads the records `ids` of `model` into `T`.
    public static func read<T: Codable & Sendable>(
        model: String,
        ids: [Int],
        fields: [String]? = nil,
        load: String? = nil,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<[T]> {
        try await execute(.read(ids: ids, fields: fields, load: load), model: model, context: context, id: id)
    }

    /// Describes the fields of `model`, keyed by field name.
    public static func fieldsGet<T: Codable & Sendable>(
        model: String,
        allfields: [String]? = nil,
        attributes: [String]? = nil,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<T> {
        try await execute(.fieldsGet(allfields: allfields, attributes: attributes), model: model, context: context, id: id)
    }

    /// Creates records, one per element of `values`, and returns their ids in order.
    /// `V` is any `Encodable` keyed by Odoo field names: `OdxParams`, or your own
    /// `Codable` struct.
    public static func create<V: Encodable & Sendable>(
        model: String,
        values: [V],
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<[Int]> {
        try await execute(.create(values: values), model: model, context: context, id: id)
    }

    /// Creates a single record and returns its id.
    public static func createOne<V: Encodable & Sendable>(
        model: String,
        values: V,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<Int> {
        let res = try await create(model: model, values: [values], context: context, id: id)
        return OdxServerResponse(jsonrpc: res.jsonrpc, id: res.id, result: res.result?.first, error: res.error)
    }

    /// Writes `values` to the records `ids`. Returns `true`.
    public static func write<V: Encodable & Sendable>(
        model: String,
        ids: [Int],
        values: V,
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<Bool> {
        try await execute(.write(ids: ids, values: values), model: model, context: context, id: id)
    }

    /// Deletes (unlinks) the records `ids`. Returns `true`.
    public static func remove(
        model: String,
        ids: [Int],
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<Bool> {
        try await execute(.remove(ids: ids), model: model, context: context, id: id)
    }

    /// Calls any public method of `model`.
    ///
    /// - Parameters:
    ///   - ids: Record ids, for record methods only. Pass `nil` for `@api.model`
    ///     methods; Odoo rejects `ids` there.
    ///   - kwargs: Every other argument under its Python parameter name. There are
    ///     no positional arguments in v2. A `"context"` entry is ignored; use
    ///     `context:` instead.
    ///
    /// ```swift
    /// let _: OdxServerResponse<Bool> = try await OdxApiV2.callMethod(model: "account.move", method: "action_post", ids: [7])
    /// let hits: OdxServerResponse<[OdxParams]> = try await OdxApiV2.callMethod(
    ///     model: "res.partner", method: "name_search", kwargs: ["name": .string("Acm"), "limit": .number(5)])
    /// ```
    public static func callMethod<T: Codable & Sendable>(
        model: String,
        method: String,
        ids: [Int]? = nil,
        kwargs: [String: OdxParams] = [:],
        context: OdxContext? = nil,
        id: String? = nil
    ) async throws -> OdxServerResponse<T> {
        try await execute(.callMethod(method, ids: ids, kwargs: kwargs), model: model, context: context, id: id)
    }

    // MARK: - Version

    /// Odoo's version over JSON-2 (`POST /v2/odoo/version`). Defaults to the
    /// configured instance URL. Throws `.json2Unavailable` when the server has no
    /// JSON-2 endpoint.
    public static func version(url: String? = nil, id: String? = nil) async throws -> OdxServerResponse<OdxV2VersionInfo> {
        let targetUrl: String
        if let url {
            targetUrl = url
        } else {
            guard let instance = client().getOdooInstance() else {
                throw OdxProxyError.notConfigured
            }
            targetUrl = instance.url
        }
        let body = OdxVersionRequest(id: id ?? ULID().ulidString, url: targetUrl)
        return try await client().postV2VersionRequest(body: body)
    }

    private actor SupportCache {
        private var answers: [String: Bool] = [:]
        func get(_ url: String) -> Bool? { answers[url] }
        func set(_ url: String, _ value: Bool) { answers[url] = value }
    }

    private static let supportCache = SupportCache()

    /// Whether the Odoo at `url` (default: the configured instance) can be reached
    /// through v2, i.e. runs Odoo 19+. Cached per URL for the life of the process.
    /// Network and proxy errors are thrown, not cached.
    public static func isSupported(url: String? = nil) async throws -> Bool {
        let target: String
        if let url {
            target = url
        } else {
            guard let instance = client().getOdooInstance() else {
                throw OdxProxyError.notConfigured
            }
            target = instance.url
        }
        if let cached = await supportCache.get(target) {
            return cached
        }
        let supported: Bool
        do {
            let res = try await version(url: target)
            supported = (res.result?.major ?? 0) >= 19
        } catch OdxProxyError.json2Unavailable {
            supported = false
        }
        await supportCache.set(target, supported)
        return supported
    }
}

/// One v2 call: Odoo method name plus its named arguments. Each public `OdxApiV2`
/// method maps its parameters through one of these constructors, which keeps the
/// parameter → wire-key mapping in one place and testable without a network.
struct OdxV2Call: Sendable {
    let method: String
    let kwargs: OdxV2Kwargs

    static func search(domain: OdxParams, offset: Int?, limit: Int?, order: String?) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("domain", domain)
        k.set("offset", offset)
        k.set("limit", limit)
        k.set("order", order)
        return OdxV2Call(method: "search", kwargs: k)
    }

    static func searchRead(domain: OdxParams?, fields: [String]?, offset: Int?, limit: Int?, order: String?) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("domain", domain)
        k.set("fields", fields)
        k.set("offset", offset)
        k.set("limit", limit)
        k.set("order", order)
        return OdxV2Call(method: "search_read", kwargs: k)
    }

    static func searchCount(domain: OdxParams, limit: Int?) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("domain", domain)
        k.set("limit", limit)
        return OdxV2Call(method: "search_count", kwargs: k)
    }

    static func read(ids: [Int], fields: [String]?, load: String?) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("ids", ids)
        k.set("fields", fields)
        k.set("load", load)
        return OdxV2Call(method: "read", kwargs: k)
    }

    static func fieldsGet(allfields: [String]?, attributes: [String]?) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("allfields", allfields)
        k.set("attributes", attributes)
        return OdxV2Call(method: "fields_get", kwargs: k)
    }

    static func create<V: Encodable & Sendable>(values: [V]) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("vals_list", values)
        return OdxV2Call(method: "create", kwargs: k)
    }

    static func write<V: Encodable & Sendable>(ids: [Int], values: V) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("ids", ids)
        k.set("vals", values)
        return OdxV2Call(method: "write", kwargs: k)
    }

    static func remove(ids: [Int]) -> OdxV2Call {
        var k = OdxV2Kwargs()
        k.set("ids", ids)
        return OdxV2Call(method: "unlink", kwargs: k)
    }

    /// A `"context"` entry in `kwargs` is dropped; the context travels through the
    /// merged `context:` parameter instead.
    static func callMethod(_ method: String, ids: [Int]?, kwargs: [String: OdxParams]) -> OdxV2Call {
        var k = OdxV2Kwargs()
        for (key, value) in kwargs where key != "context" {
            k.set(key, value)
        }
        k.set("ids", ids)
        return OdxV2Call(method: method, kwargs: k)
    }
}
