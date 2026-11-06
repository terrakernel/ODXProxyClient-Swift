import Foundation

/// ODXBrain through ODXProxy (`/brain/v1/*`, ODXProxy 0.10.0+): which Odoo model
/// holds some data, and which SOP covers a task. Meant for an LLM planning Odoo
/// calls, followed by `fieldsGet` on the chosen model for the real fields.
///
/// ODXBrain is an optional sidecar, and its calls need no Odoo credentials: they use
/// the same `OdxProxyClient.shared.configure(with:)` and `x-api-key` as `OdxApi`,
/// but never send `odoo_instance`.
///
/// - Check `isAvailable()` first, or catch `OdxProxyError.brainNotInstalled`, to
///   hide the feature on a proxy without ODXBrain. Never retry that one.
/// - Every candidate is returned, in ODXBrain's order. Don't filter on `score`.
/// - ODXBrain's own errors (bad input, an index not loaded) arrive as
///   `.brainError`; branch on `brainErrorType`.
/// - The proxy gives ODXBrain 5 seconds by default. Keep `configure(timeout:)`
///   above that, or the client gives up just before the proxy answers.
///
/// ```swift
/// if try await OdxBrain.isAvailable() {
///     let facts = try await OdxApiV2.brainFacts()
///     let res = try await OdxBrain.resolveModel(
///         query: "which invoice is not paid yet",
///         odooVersion: facts.odooVersion,
///         edition: facts.edition
///     )
///     for candidate in res.result?.candidates ?? [] {
///         // fieldsGet(model: candidate.model) ...
///     }
/// }
/// ```
public enum OdxBrain {

    private static func client() -> OdxProxyClient {
        OdxProxyClient.shared
    }

    // MARK: - Feature probe

    /// Whether this proxy is configured for ODXBrain: `features.odxbrain` from
    /// `GET /_/about`. A proxy older than 0.10.0 sends no `features`, which reads as
    /// `false`. `true` doesn't mean ODXBrain is up right now. Not cached.
    public static func isAvailable() async throws -> Bool {
        let about = try await client().getAboutInfo()
        return about.result?.hasFeature("odxbrain") ?? false
    }

    // MARK: - Resolve

    /// `POST /brain/v1/resolve`: ranked Odoo models for a question.
    ///
    /// - Parameters:
    ///   - query: The question, in any language ODXBrain supports.
    ///   - odooVersion: Odoo's serie, e.g. `"19.0"`. Omitted when `nil`, which
    ///     filters nothing. Get it from `OdxApi.brainFacts()` /
    ///     `OdxApiV2.brainFacts()`; never guess.
    ///   - edition: Omitted when `nil`.
    ///   - k: How many candidates to return (ODXBrain's default is 3).
    ///   - extra: Fields this SDK doesn't know yet, forwarded unchanged. The named
    ///     parameters win over the same key here, and an `id` key is ignored.
    public static func resolveModel(
        query: String,
        odooVersion: String? = nil,
        edition: OdxBrainEdition? = nil,
        k: Int? = nil,
        extra: [String: OdxParams] = [:],
        id: String? = nil
    ) async throws -> OdxServerResponse<OdxBrainModelResolution> {
        let body = makeRequest(
            .resolveModel(query: query, odooVersion: odooVersion, edition: edition, k: k, extra: extra),
            id: id
        )
        return try await client().postBrainResolve(body: body)
    }

    /// `POST /brain/v1/sops/resolve`: ranked SOPs for a task.
    ///
    /// If the result's `match` is `"none"`, no SOP is a confident match: ask the
    /// user instead of running the nearest one.
    ///
    /// - Parameters:
    ///   - installedModules: Installed module names (`ir.module.module` with state
    ///     `installed`). Omitted when `nil`.
    ///   - company: The key the SOPs were published under. Omitted when `nil`.
    ///   - k: Capped at 10 by ODXBrain.
    ///   - The rest: as for `resolveModel`.
    public static func resolveSOP(
        query: String,
        odooVersion: String? = nil,
        edition: OdxBrainEdition? = nil,
        installedModules: [String]? = nil,
        company: String? = nil,
        k: Int? = nil,
        extra: [String: OdxParams] = [:],
        id: String? = nil
    ) async throws -> OdxServerResponse<OdxBrainSOPResolution> {
        let body = makeRequest(
            .resolveSOP(query: query, odooVersion: odooVersion, edition: edition,
                        installedModules: installedModules, company: company, k: k, extra: extra),
            id: id
        )
        return try await client().postBrainSOPsResolve(body: body)
    }

    // MARK: - Info

    /// `GET /brain/v1/info`: what this deployment's ODXBrain can answer (embedding
    /// model, corpus and SOP set loaded, Odoo version range covered), as ODXBrain's
    /// raw JSON. The response `id` is `null`, which decodes as `""`.
    public static func info() async throws -> OdxServerResponse<OdxParams> {
        try await client().getBrainInfo()
    }

    // MARK: - Request building

    /// Builds the wire body. Pure, so unit tests can check the exact JSON.
    static func makeRequest(_ fields: OdxBrainCall, id: String?) -> OdxBrainRequest {
        OdxBrainRequest(id: id ?? ULID().ulidString, fields: fields.fields)
    }
}

/// The fields of one ODXBrain call, keyed by ODXBrain's wire names. Keeps the
/// parameter → wire-key mapping in one place and testable without a network.
struct OdxBrainCall: Sendable {
    let fields: OdxV2Kwargs

    static func resolveModel(query: String, odooVersion: String?, edition: OdxBrainEdition?,
                             k: Int?, extra: [String: OdxParams]) -> OdxBrainCall {
        var f = base(extra)
        f.set("query", query)
        f.set("odoo_version", odooVersion)
        f.set("edition", edition)
        f.set("k", k)
        return OdxBrainCall(fields: f)
    }

    static func resolveSOP(query: String, odooVersion: String?, edition: OdxBrainEdition?,
                           installedModules: [String]?, company: String?, k: Int?,
                           extra: [String: OdxParams]) -> OdxBrainCall {
        var f = base(extra)
        f.set("query", query)
        f.set("odoo_version", odooVersion)
        f.set("edition", edition)
        f.set("installed_modules", installedModules)
        f.set("company", company)
        f.set("k", k)
        return OdxBrainCall(fields: f)
    }

    /// `extra` first, so the named parameters overwrite it. `id` is set by the request.
    private static func base(_ extra: [String: OdxParams]) -> OdxV2Kwargs {
        var f = OdxV2Kwargs()
        for (key, value) in extra where key != "id" {
            f.set(key, value)
        }
        return f
    }
}

// MARK: - Facts from the version endpoints

/// Caches `brainFacts` per Odoo URL for the life of the process.
private actor BrainFactsCache {
    static let shared = BrainFactsCache()
    private var facts: [String: OdxBrainFacts] = [:]
    func get(_ url: String) -> OdxBrainFacts? { facts[url] }
    func set(_ url: String, _ value: OdxBrainFacts) { facts[url] = value }
}

extension OdxApi {
    /// The `odooVersion` and `edition` to pass to `OdxBrain`, from v1's version
    /// endpoint for `url` (default: the configured instance). Cached per URL.
    /// Errors are thrown, not cached.
    public static func brainFacts(url: String? = nil) async throws -> OdxBrainFacts {
        let target = try brainFactsTarget(url)
        if let cached = await BrainFactsCache.shared.get(target) { return cached }
        let res: OdxServerResponse<[String: OdxParams]> = try await version(url: target)
        guard let result = res.result else { return OdxBrainFacts() }
        let facts = OdxBrainFacts.fromV1(result)
        await BrainFactsCache.shared.set(target, facts)
        return facts
    }
}

extension OdxApiV2 {
    /// The `odooVersion` and `edition` to pass to `OdxBrain`, from v2's version
    /// endpoint for `url` (default: the configured instance). Cached per URL.
    /// Throws `.json2Unavailable` on Odoo 18 and older; use `OdxApi.brainFacts` there.
    public static func brainFacts(url: String? = nil) async throws -> OdxBrainFacts {
        let target = try brainFactsTarget(url)
        if let cached = await BrainFactsCache.shared.get(target) { return cached }
        let res = try await version(url: target)
        guard let result = res.result else { return OdxBrainFacts() }
        let facts = OdxBrainFacts.fromV2(result)
        await BrainFactsCache.shared.set(target, facts)
        return facts
    }
}

private func brainFactsTarget(_ url: String?) throws -> String {
    if let url { return url }
    guard let instance = OdxProxyClient.shared.getOdooInstance() else {
        throw OdxProxyError.notConfigured
    }
    return instance.url
}
