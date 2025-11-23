import Foundation

// MARK: - OdxProxyClient
@MainActor
public final class OdxProxyClient {
    public static let shared = OdxProxyClient()

    private var api: URLSession!
    private var apiKey: String?
    private var gatewayUrl: URL?
    private var odooInstance: OdxInstanceInfo?

    private init() {}

    public func configure(with options: OdxProxyClientInfo, timeout: Int?) {
        self.odooInstance = options.instance
        self.apiKey = options.odxApiKey

        var gatewayUrlString = options.gatewayUrl ?? "https://gateway.odxproxy.io"
        if gatewayUrlString.hasSuffix("/") {
            gatewayUrlString = String(gatewayUrlString.dropLast())
        }
        self.gatewayUrl = URL(string: gatewayUrlString)

        let configuration = URLSessionConfiguration.default
        let _timeout = TimeInterval(timeout ?? 60)
        configuration.timeoutIntervalForRequest = _timeout
        configuration.httpAdditionalHeaders = [
            "accept": "application/json",
            "content-type": "application/json",
            "x-api-key": options.odxApiKey,
            "user-agent": "ODXProxyClient-Swift",
            "accept-encoding": "gzip,deflate,br"
        ]
        self.api = URLSession(configuration: configuration)
    }

    internal func getOdooInstance() -> OdxInstanceInfo? {
        return odooInstance
    }

    internal func postRequest<T: Codable & Sendable>(body: OdxClientRequest) async throws -> OdxServerResponse<T> {
        guard let gatewayUrl = self.gatewayUrl else {
            throw OdxProxyError.notConfigured
        }

        let url = gatewayUrl.appendingPathComponent("/api/odoo/execute")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Handles big body gracefully
        let encodedBody = try await JSONEncoder.encodeInBackground(body)
        request.httpBody = encodedBody

        do {
            let (data, response) = try await api.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OdxProxyError.invalidResponse(nil)
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorResponse = try? JSONDecoder().decode(OdxServerErrorResponse.self, from: data)
                throw OdxProxyError.serverError(errorResponse ?? OdxServerErrorResponse(code: httpResponse.statusCode, message: "Unknown server error", data: nil))
            }
            // Move to another thread so if a large json is returned wont stale the UI
            let decodedResponse = try await JSONDecoder.decodeInBackground(OdxServerResponse<T>.self, from: data)
            return decodedResponse
        } catch let error as OdxProxyError {
            throw error
        } catch {
            throw OdxProxyError.networkError(error)
        }
    }
}
