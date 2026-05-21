import Foundation

// MARK: - OdxProxyClient
public final class OdxProxyClient: @unchecked Sendable {
    public static let shared = OdxProxyClient()

    private struct Config: Sendable {
        let session: URLSession
        let executeURL: URL
        let versionURL: URL
        let aboutURL: URL
        let licenseURL: URL
        let odooInstance: OdxInstanceInfo
    }

    private let lock = NSLock()
    private var config: Config?
    private var configurationError: OdxProxyError?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    public func configure(with options: OdxProxyClientInfo, timeout: Int? = nil) {
        var gatewayUrlString = options.gatewayUrl ?? "https://gateway.odxproxy.io"
        if gatewayUrlString.hasSuffix("/") {
            gatewayUrlString = String(gatewayUrlString.dropLast())
        }
        guard let gatewayUrl = URL(string: gatewayUrlString) else {
            lock.lock()
            let previousSession = config?.session
            config = nil
            configurationError = .invalidURL
            lock.unlock()
            previousSession?.finishTasksAndInvalidate()
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(timeout ?? 60)
        configuration.httpAdditionalHeaders = [
            "accept": "application/json",
            "content-type": "application/json",
            "x-api-key": options.odxApiKey,
            "user-agent": "ODXProxyClient-Swift",
            "accept-encoding": "gzip,deflate,br"
        ]
        let session = URLSession(configuration: configuration)

        let newConfig = Config(
            session: session,
            executeURL: gatewayUrl.appendingPathComponent("/api/odoo/execute"),
            versionURL: gatewayUrl.appendingPathComponent("/api/odoo/version"),
            aboutURL:   gatewayUrl.appendingPathComponent("/_/about"),
            licenseURL: gatewayUrl.appendingPathComponent("/_/license"),
            odooInstance: options.instance
        )

        lock.lock()
        let previousSession = config?.session
        config = newConfig
        configurationError = nil
        lock.unlock()

        previousSession?.finishTasksAndInvalidate()
    }

    internal func getOdooInstance() -> OdxInstanceInfo? {
        lock.lock()
        defer { lock.unlock() }
        return config?.odooInstance
    }

    private func snapshotConfig() throws -> Config {
        lock.lock()
        defer { lock.unlock() }
        if let config = config { return config }
        if let err = configurationError { throw err }
        throw OdxProxyError.notConfigured
    }

    // MARK: - Internal request helpers

    /// POST an Encodable body to `url`, decoding the response as a JSON-RPC
    /// envelope `OdxServerResponse<T>`. Maps `error` objects through
    /// `OdxProxyError.from(_:httpStatus:)` so the caller catches a typed error.
    private func postEnvelope<B: Encodable & Sendable, T: Codable & Sendable>(
        snapshot: Config,
        url: URL,
        body: B
    ) async throws -> OdxServerResponse<T> {
        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await snapshot.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdxProxyError.invalidResponse(nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let parsed = try? decoder.decode(OdxServerResponse<T>.self, from: data)
            let raw = parsed?.error ?? OdxServerErrorResponse(
                code: httpResponse.statusCode,
                message: "Unknown server error",
                data: nil
            )
            throw OdxProxyError.from(raw, httpStatus: httpResponse.statusCode)
        }

        try Task.checkCancellation()

        let decodedResponse: OdxServerResponse<T>
        do {
            decodedResponse = try decoder.decode(OdxServerResponse<T>.self, from: data)
        } catch let error as DecodingError {
            throw OdxProxyError.decodingError(error)
        }
        if let error = decodedResponse.error {
            throw OdxProxyError.from(error, httpStatus: httpResponse.statusCode)
        }
        return decodedResponse
    }

    /// GET a flat JSON object from `url`, decoding directly as `T`.
    /// Used for endpoints whose response is NOT a JSON-RPC envelope (e.g. `/_/license`).
    private func getRaw<T: Decodable & Sendable>(
        snapshot: Config,
        url: URL
    ) async throws -> T {
        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await snapshot.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdxProxyError.invalidResponse(nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OdxProxyError.invalidResponse(httpResponse)
        }

        try Task.checkCancellation()

        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw OdxProxyError.decodingError(error)
        }
    }

    // MARK: - Endpoints used by OdxApi / OdxOps

    internal func postExecuteRPC<T: Codable & Sendable>(
        body: OdxClientRequest
    ) async throws -> OdxServerResponse<T> {
        let snapshot = try snapshotConfig()
        return try await postEnvelope(snapshot: snapshot, url: snapshot.executeURL, body: body)
    }

    internal func postVersionRequest<T: Codable & Sendable>(
        body: OdxVersionRequest
    ) async throws -> OdxServerResponse<T> {
        let snapshot = try snapshotConfig()
        return try await postEnvelope(snapshot: snapshot, url: snapshot.versionURL, body: body)
    }

    internal func getAboutInfo() async throws -> OdxServerResponse<OdxAboutInfo> {
        let snapshot = try snapshotConfig()
        return try await getRaw(snapshot: snapshot, url: snapshot.aboutURL)
    }

    internal func getLicenseInfo() async throws -> OdxLicenseInfo {
        let snapshot = try snapshotConfig()
        return try await getRaw(snapshot: snapshot, url: snapshot.licenseURL)
    }
}
