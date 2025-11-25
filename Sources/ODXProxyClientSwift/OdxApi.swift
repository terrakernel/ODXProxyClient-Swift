import Foundation

@MainActor
public enum OdxApi {
    
    
    private static func client() -> OdxProxyClient {
        return OdxProxyClient.shared
    }

    /// Executes an Odoo `search` RPC call and returns an array of matching record IDs.
    ///
    /// This method performs an Odoo `search` operation using the provided model,
    /// parameters, and keyword request. It automatically strips pagination and
    /// ordering options from the keyword request, as they are not applicable for
    /// the basic `search` action (which returns only IDs).
    ///
    /// If an explicit `id` is not provided, a ULID string will be generated.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name to query (e.g. `"res.partner"`).
    ///   - params: An `OdxParams` instance containing domain filters and other search arguments.
    ///   - keyword: The keyword request object describing search metadata.
    ///              Pagination and ordering fields will be ignored for this call.
    ///   - id: Optional request ID. If omitted, a ULID will be automatically generated.
    ///
    /// - Returns: An `OdxServerResponse` containing an array of `Int` record IDs returned by Odoo.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if the Odoo instance is not configured.
    ///   - Any error thrown by the underlying HTTP client or `postRequest`.
    ///
    /// - Note:
    ///   This call only returns record IDs.
    ///   If you need full records, use `searchRead` instead.
    ///
    /// - SeeAlso: `searchRead(model:params:keyword:id:)`
    ///
    /// - Example:
    /// ```swift
    /// let ids = try await OdxClient.search(
    ///     model: "res.partner",
    ///     params: OdxParams([["is_company", "=", true]]),
    ///     keyword: OdxClientKeywordRequest()
    /// )
    /// print(ids.result) // [1, 5, 9, ...]
    /// ```
    public static func search(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<[Int]> {
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
    
    /// Executes an Odoo `search_read` RPC call and returns a typed list of records.
    ///
    /// This method performs the combined `search_read` operation commonly used in Odoo,
    /// allowing you to filter records using `params` and immediately return fully
    /// populated model objects of type `T`.
    ///
    /// The function automatically encodes the request with a generated ULID if
    /// an explicit `id` is not provided.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name to query (e.g. `"res.partner"`).
    ///   - params: An `OdxParams` instance containing the domain filters and search parameters.
    ///   - keyword: A keyword request describing pagination, ordering, and fields.
    ///   - id: Optional request ID. If `nil`, a ULID string will be automatically generated.
    ///
    /// - Returns: An `OdxServerResponse` containing an array of decoded objects of type `T`.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if the Odoo instance was never set.
    ///   - Any encoding/decoding or network error thrown by `postRequest`.
    ///
    /// - Note:
    ///   This call returns **full model records**, not just IDs. It is equivalent to
    ///   Odoo's `search_read` JSON-RPC method.
    ///
    /// - SeeAlso:
    ///   - `search(model:params:keyword:id:)` for ID-only lookups.
    ///   - `read` or `fields_get` if you need schema information.
    ///
    /// - Example:
    /// ```swift
    /// struct Partner: Codable {
    ///     let id: Int
    ///     let name: String
    /// }
    ///
    /// let partners = try await OdxClient.searchRead(
    ///     model: "res.partner",
    ///     params: OdxParams([["is_company", "=", true]]),
    ///     keyword: OdxClientKeywordRequest(limit: 50)
    /// )
    ///
    /// print(partners.result.first?.name ?? "none")
    /// ```
    public static func searchRead<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<[T]> {
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

    
    public static func read<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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

    /// Retrieves the full field metadata definition of an Odoo model using the
    /// `fields_get` RPC call.
    ///
    /// This method queries Odoo for the schema of a given model. It returns a
    /// dictionary-like structure where each key represents a field name, and each value
    /// is the corresponding field metadata (type, help text, relation info, etc.).
    ///
    /// Keyword parameters like `order`, `limit`, `offset`, and `fields` are automatically
    /// stripped out because `fields_get` does not use them.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name to inspect (e.g. `"res.partner"`).
    ///   - keyword: A keyword request object. All pagination and ordering options are ignored.
    ///   - id: Optional RPC request ID. A ULID will be generated automatically when omitted.
    ///
    /// - Returns:
    ///   An `OdxServerResponse<T>` where `T` represents the decoded metadata structure.
    ///   This is typically a dictionary type, e.g.:
    ///   ```swift
    ///   [String: OdooFieldInfo]
    ///   ```
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if the Odoo instance is not set.
    ///   - Any error thrown by the JSON encoder/decoder or the network client.
    ///
    /// - Important:
    ///   Odoo’s `fields_get` returns the schema **not actual record values**.
    ///   This is useful for building dynamic UIs, editors, or model introspection tools.
    ///
    /// - SeeAlso:
    ///   - `searchRead` for fetching actual record values.
    ///   - `search` for ID-only lookups.
    ///   - `read` for fetching specific records.
    ///
    /// - Example:
    /// ```swift
    /// struct FieldInfo: Codable {
    ///     let type: String
    ///     let string: String?
    ///     let relation: String?
    /// }
    ///
    /// let fields = try await OdxClient.fieldsGet(
    ///     model: "res.partner",
    ///     keyword: OdxClientKeywordRequest()
    /// )
    ///
    /// print(fields.result["name"]?.type ?? "Unknown")
    /// ```
    public static func fieldsGet<T: Codable & Sendable>(model: String, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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
            params: OdxParams([]),
            odooInstance: odooInstance
        )
        
        return try await client().postRequest(body: body)
    }

    /// Counts the number of records matching the given search domain.
    ///
    /// This method sends a `search_count` request to the Odoo backend and
    /// returns the number of records that match the provided `params` and `keyword`.
    ///
    /// The `keyword` fields related to pagination (`order`, `limit`, `offset`, `fields`)
    /// are removed because `search_count` does not use them.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name to query (e.g., `"res.partner"`).
    ///   - params: The domain parameters (`OdxParams`) used to filter records.
    ///   - keyword: An `OdxClientKeywordRequest` used for additional filters.
    ///              Pagination-related properties are ignored for this action.
    ///   - id: Optional request identifier. If omitted, a ULID will be generated.
    /// - Returns: An `OdxServerResponse<Int>` containing the count of matching records.
    /// - Throws: `OdxProxyError.notConfigured` if the Odoo instance is not configured,
    ///           or any networking/decoding errors from `postRequest`.
    ///
    public static func searchCount(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<Int> {
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

    /// Creates a new record on an Odoo model using the `create` RPC action.
    ///
    /// This method sends a payload containing field values (`params`) to Odoo and
    /// returns the created record’s ID or any additional data the Odoo model returns.
    ///
    /// The `create` operation in Odoo usually returns the newly created record ID,
    /// but depending on your backend, your proxy may return any structure of type `T`.
    ///
    /// All pagination- or ordering-related keyword fields (`order`, `limit`, `offset`,
    /// `fields`) are intentionally cleared because they are irrelevant to model creation.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name in which the record will be created (e.g. `"res.partner"`).
    ///   - params: An `OdxParams` object representing the field values for the new record.
    ///             Supports nested arrays, dictionaries, and false/null semantics for Odoo.
    ///   - keyword: Additional keyword parameters. Pagination and ordering options are ignored.
    ///   - id: An optional RPC request identifier. A new ULID is generated automatically if omitted.
    ///
    /// - Returns:
    ///   An `OdxServerResponse<T>` containing the server's response, typically:
    ///   - The newly created record ID (`Int`)
    ///   - Or a structured response depending on backend behavior.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if no Odoo instance is configured.
    ///   - Any error from encoding/decoding or the network layer.
    ///
    /// - Example:
    /// ```swift
    /// let params = OdxParams([
    ///     "name": "New Partner",
    ///     "email": "test@example.com"
    /// ])
    ///
    /// let result = try await OdxClient.create(
    ///     model: "res.partner",
    ///     params: params,
    ///     keyword: OdxClientKeywordRequest()
    /// )
    ///
    /// print("Created ID:", result.result)
    /// ```
    ///
    /// - Important:
    ///   Ensure your `params` object only contains fields allowed by the model.
    ///   Odoo will throw a validation error on unknown fields.
    ///
    public static func create<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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

    
    /// Deletes one or more records from an Odoo model using the `unlink` RPC action.
    ///
    /// This method sends a list of record IDs (or any structure wrapped in `OdxParams`)
    /// to Odoo and requests deletion. The `unlink` action removes the specified records
    /// permanently, assuming the model allows deletion and no constraints block it.
    ///
    /// All pagination- or ordering-related keyword fields (`order`, `limit`, `offset`,
    /// `fields`) are ignored and automatically cleared since they do not apply to delete
    /// operations.
    ///
    /// - Parameters:
    ///   - model: The Odoo model name from which records will be removed
    ///            (e.g. `"product.product"`).
    ///   - params: An `OdxParams` object containing the record IDs to delete.
    ///             Typically something like:
    ///             `OdxParams([1, 2, 3])`
    ///   - keyword: Additional keyword configuration. All pagination-related fields
    ///              will be set to `nil`.
    ///   - id: Optional RPC request identifier. A new ULID will be generated if omitted.
    ///
    /// - Returns:
    ///   An `OdxServerResponse<T>` which typically returns:
    ///   - A boolean (`true`) meaning success, OR
    ///   - Any backend-defined structure of type `T`.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if no Odoo instance is configured.
    ///   - Errors related to encoding, decoding, or networking.
    ///
    /// - Example:
    /// ```swift
    /// let params = OdxParams([10, 11, 12])  // Delete these product IDs
    ///
    /// let response = try await OdxClient.remove(
    ///     model: "product.product",
    ///     params: params,
    ///     keyword: OdxClientKeywordRequest()
    /// )
    ///
    /// print("Delete result:", response.result)
    /// ```
    ///
    /// - Important:
    ///   Deleting records in Odoo may fail if constraints or business logic prevent it.
    ///   For example, products linked to stock movements cannot be deleted.
    ///
    public static func remove<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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
    
    /// Updates one or more records in an Odoo model using the `write` RPC action.
    ///
    /// This method performs an update operation on existing records by sending
    /// both the record IDs and the updated field values. The update is expressed
    /// using the `params` argument, typically formatted as:
    ///
    /// ```swift
    /// OdxParams([ [ids], [field: value] ])
    /// ```
    ///
    /// All pagination- and ordering-related keyword fields (`order`, `limit`,
    /// `offset`, `fields`) are ignored and cleared automatically since they are not
    /// applicable for update operations.
    ///
    /// - Parameters:
    ///   - model: The name of the Odoo model whose records should be updated
    ///            (e.g. `"product.template"`).
    ///   - params: An `OdxParams` structure representing the record IDs and updated
    ///             field values. Example:
    ///             ```swift
    ///             OdxParams([ [10, 12], ["name": "New Name"] ])
    ///             ```
    ///   - keyword: Additional keyword options. Pagination fields will be set to nil.
    ///   - id: Optional request ID. A new ULID will be generated if omitted.
    ///
    /// - Returns:
    ///   An `OdxServerResponse<T>` containing the server's response. Odoo typically
    ///   returns a boolean (`true`) indicating success, but your server wrapper may
    ///   return additional data depending on configuration.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if the client has no active Odoo instance.
    ///   - Any encoding/decoding/network-related errors.
    ///
    /// - Example:
    /// ```swift
    /// let params = OdxParams([
    ///     [42],                        // Record IDs
    ///     ["name": "Updated Product"]  // Fields to update
    /// ])
    ///
    /// let response: OdxServerResponse<Bool> = try await OdxApi.write(
    ///     model: "product.product",
    ///     params: params,
    ///     keyword: OdxClientKeywordRequest()
    /// )
    ///
    /// print("Update success:", response.result)
    /// ```
    ///
    /// - Important:
    ///   Update operations may be blocked by Odoo business logic or access rights.
    ///   If a field is readonly or forbidden, Odoo will return an error.
    ///
    public static func write<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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

    /// Aliases to Write
    public static func update<T: Codable & Sendable>(model: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
        return try await write(model: model, params: params, keyword: keyword, id: id)
    }

    /// Calls a custom or built-in method on an Odoo model using the `call_method` RPC action.
    ///
    /// This function allows you to execute *any* server-side method exposed by an
    /// Odoo model, including custom Python methods added via modules. The method
    /// name is provided through `functionName`, and the arguments are passed using
    /// `params`, typically formatted as:
    ///
    /// ```swift
    /// OdxParams([ [args], { kwargs } ])
    /// ```
    ///
    /// All list-related keyword parameters (`order`, `limit`, `offset`, `fields`)
    /// are automatically cleared since method calls do not use pagination.
    ///
    /// - Parameters:
    ///   - model: The Odoo model on which the method will be invoked
    ///            (e.g. `"stock.picking"`).
    ///   - functionName: The exact name of the Python method to call.
    ///                   Example: `"action_confirm"`, `"compute_totals"`.
    ///   - params: An `OdxParams` structure representing positional and keyword
    ///             arguments to the method.
    ///   - keyword: Additional keyword metadata. Pagination fields are ignored.
    ///   - id: Optional request ID. A ULID is generated automatically if omitted.
    ///
    /// - Returns:
    ///   An `OdxServerResponse<T>` containing whatever data the custom method
    ///   returns — a boolean, dictionary, array, or model-like response.
    ///
    /// - Throws:
    ///   - `OdxProxyError.notConfigured` if no active Odoo instance exists.
    ///   - Any network, encoding, or server-side exception from Odoo.
    ///
    /// - Example:
    /// ```swift
    /// // Example: call button method "action_confirm" on sale.order
    /// let params = OdxParams([ [42] ])   // calling with record ID 42
    ///
    /// let result: OdxServerResponse<Bool> = try await OdxApi.callMethod(
    ///     model: "sale.order",
    ///     functionName: "action_confirm",
    ///     params: params,
    ///     keyword: OdxClientKeywordRequest()
    /// )
    ///
    /// print("Confirmed:", result.result)
    /// ```
    ///
    /// - Important:
    ///   This is the most powerful and dangerous RPC call. If the method raises
    ///   exceptions in Odoo, they will propagate back as errors. Always validate
    ///   expected inputs.
    ///
    public static func callMethod<T: Codable & Sendable>(model: String, functionName: String, params: OdxParams, keyword: OdxClientKeywordRequest, id: String? = nil) async throws -> OdxServerResponse<T> {
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
