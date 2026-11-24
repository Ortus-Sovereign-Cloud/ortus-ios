// Notifications while the app is closed. The phone registers with its
// installation and gets a fetch token; a push names only a notification's
// id and the installation, and the notification extension fetches the
// text itself with that token (which can do nothing else).
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What registering gave back: the device's id (to unregister) and the
/// fetch token, kept where the notification extension can read it.
public struct PushRegistration: Codable, Equatable, Sendable {
    public let id: String
    public let fetch_token: String

    public init(id: String, fetch_token: String) {
        self.id = id
        self.fetch_token = fetch_token
    }
}

/// One notification as the extension shows it.
public struct PushNotice: Decodable, Equatable, Sendable {
    public let app: String
    public let title: String
    public let detail: String?
    public let path: String?
}

public enum Push {
    /// Apple's device token, as the installation takes it.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// The push's notification id and installation, if it is one of ours.
    public static func parts(of userInfo: [AnyHashable: Any]) -> (id: String, server: URL)? {
        guard let id = userInfo["n"] as? String, !id.isEmpty, id.count <= 64,
              let s = userInfo["s"] as? String, let server = Client.serverURL(from: s), server.absoluteString == s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        else { return nil }
        return (id, server)
    }

    /// The text of one notification, with the fetch token.
    public static func fetch(server: URL, fetchToken: String, id: String, transport: Transport = URLSessionTransport()) async throws -> PushNotice {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        var r = URLRequest(url: URL(string: server.absoluteString + "/api/v1/push/notices/" + safe)!)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue(fetchToken, forHTTPHeaderField: "X-Ortus-Push")
        r.timeoutInterval = 20
        let (status, data) = try await transport.send(r)
        guard status == 200 else { throw APIError(status: status, code: "http_\(status)", message: "") }
        return try JSONDecoder().decode(PushNotice.self, from: data)
    }

    /// The room a call's path names (`/calls?room=…`).
    public static func callRoom(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/calls"), let items = URLComponents(string: path)?.queryItems else { return nil }
        return items.first { $0.name == "room" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Which tab a notification's path opens: 0 Mail, 1 Chat, 2 Calendar,
    /// 3 Drive, 4 More.
    public static func tab(for path: String?) -> Int {
        let p = path ?? ""
        if p.hasPrefix("/mail") { return 0 }
        if p.hasPrefix("/chat") || p.hasPrefix("/calls") { return 1 }
        if p.hasPrefix("/calendar") { return 2 }
        if p.hasPrefix("/drive") || p.hasPrefix("/docs") { return 3 }
        return 4
    }
}

extension Client {
    /// Registers this phone for its person's notifications.
    /// `voip`: the phone's PushKit token, on which calls ring.
    public func registerPush(token: Data, voip: Data? = nil, sandbox: Bool, utcOffsetMinutes: Int) async throws -> PushRegistration {
        var body: [String: Any] = [
            "platform": "apns",
            "token": Push.hex(token),
            "environment": sandbox ? "sandbox" : "production",
            "utc_offset": utcOffsetMinutes,
        ]
        if let voip { body["voip"] = Push.hex(voip) }
        return try await call("POST", "/me/push-devices", json: body)
    }

    public func unregisterPush(id: String) async throws {
        struct Ignored: Decodable {}
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let _: Ignored = try await call("DELETE", "/me/push-devices/" + safe)
    }
}
