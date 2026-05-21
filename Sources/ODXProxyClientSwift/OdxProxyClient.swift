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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    public func configure(with options: OdxProxyClientInfo, timeout: Int?) {
        var gatewayUrlString = options.gatewayUrl ?? "https://gateway.odxproxy.io"
        if gatewayUrlString.hasSuffix("/") {
            gatewayUrlString = String(gatewayUrlString.dropLast())
        }
        guard let gatewayUrl = URL(string: gatewayUrlString) else {
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
        guard let config = config else {
            throw OdxProxyError.notConfigured
        }
        return config
    }

    internal func postRequest<T: Codable & Sendable>(body: OdxClientRequest) async throws -> OdxServerResponse<T> {
        let snapshot = try snapshotConfig()

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

        let decodedResponse = try decoder.decode(OdxServerResponse<T>.self, from: data)
        if let error = decodedResponse.error {
            throw OdxProxyError.serverError(error)
        }
        return decodedResponse
    }
}
