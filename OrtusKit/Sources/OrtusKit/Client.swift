// The Ortus API as the phone uses it: JSON over HTTPS, the session token
// as `Authorization: Bearer`, and `X-Requested-With: ortus` on changes,
// like the web client.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIError: Error, Equatable, LocalizedError {
    public let status: Int
    public let code: String
    public let message: String
    public var errorDescription: String? { message }

    public init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }
}

/// Sends a request and gives back the status and body (stubbed in tests).
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Int, Data)
}

/// URLSession without cookies or a disk cache: the session lives only in
/// the Keychain (the server's Set-Cookie is never kept).
public struct URLSessionTransport: Transport {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public init() {}
    public func send(_ request: URLRequest) async throws -> (Int, Data) {
        let (data, response) = try await Self.session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

public final class Client: @unchecked Sendable {
    public let server: URL
    public var token: String?
    let transport: Transport

    public init(server: URL, token: String? = nil, transport: Transport = URLSessionTransport()) {
        self.server = server
        self.token = token
        self.transport = transport
    }

    /// The server address a person typed: https added when missing.
    public static func serverURL(from typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return nil }
        // An installation lives at its origin: "Ortus.Example:443/x" is https://ortus.example.
        return URL(string: WebAuthn.origin(publicURL: url.absoluteString))
    }

    public func request(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: server.absoluteString + "/api/v1" + path)!)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" { r.setValue("ortus", forHTTPHeaderField: "X-Requested-With") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = body
        }
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    /// Calls the API; a JSON body in, the decoded answer out.
    public func call<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil, as: T.Type = T.self) async throws -> T {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, data) = try await transport.send(request(method, path, body: body))
        guard (200..<300).contains(status) else {
            let e = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = e?["error"] as? [String: Any] ?? e ?? [:]
            throw APIError(status: status, code: error["code"] as? String ?? "http_\(status)", message: error["message"] as? String ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }
}
