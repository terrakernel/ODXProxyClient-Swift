import Foundation

// MARK: - OdxProxyClient
public final class OdxProxyClient: @unchecked Sendable {
    public static let shared = OdxProxyClient()

    private struct Config: Sendable {
        let session: URLSession
        let executeURL: URL
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
        let executeURL = gatewayUrl.appendingPathComponent("/api/odoo/execute")

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

        let newConfig = Config(session: session, executeURL: executeURL, odooInstance: options.instance)

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

    internal func postRequest<T: Codable & Sendable>(body: OdxClientRequest) async throws -> OdxServerResponse<T> {
        let snapshot = try snapshotConfig()

        try Task.checkCancellation()

        var request = URLRequest(url: snapshot.executeURL)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await snapshot.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OdxProxyError.invalidResponse(nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? decoder.decode(OdxServerResponse<T>.self, from: data)
            throw OdxProxyError.serverError(errorResponse?.error ?? OdxServerErrorResponse(code: httpResponse.statusCode, message: "Unknown server error", data: nil))
        }

        try Task.checkCancellation()

        let decodedResponse: OdxServerResponse<T>
        do {
            decodedResponse = try decoder.decode(OdxServerResponse<T>.self, from: data)
        } catch let error as DecodingError {
            throw OdxProxyError.decodingError(error)
        }
        if let error = decodedResponse.error {
            throw OdxProxyError.serverError(error)
        }
        return decodedResponse
    }
}
