// The bell and search.
import Foundation

public struct Notice: Decodable, Equatable, Identifiable {
    public let id: String
    public let app: String
    public let kind: String
    public let title: String
    public let detail: String?
    public let path: String?
    public let at: Int64
    public let read: Bool
    public var date: Date { Date(timeIntervalSince1970: Double(at) / 1000) }
}

public struct SearchHit: Decodable, Equatable, Identifiable {
    /// What the app that indexed it adds: where it opens on the web, and
    /// when an event starts (an older installation may send none).
    public struct Meta: Decodable, Equatable {
        public let path: String?
        public let start: Int64?
        public let from: String?
    }
    public let app: String
    public let id: String
    public let title: String
    public let snippet: String?
    public let at: Int64?
    public let meta: Meta?
    public var key: String { app + ":" + id }
    /// Where it opens: the web's path, or the app's own page as the web does.
    public var place: Place { Place(path: meta?.path ?? "/" + app, start: meta?.start) }
}

/// Where a web path (a search result's, a notification's) opens on the
/// phone: one of the app's screens, or else the web page itself.
public enum Place: Hashable, Sendable {
    case thread(String)
    case room(String)
    case doc(String)
    case folder(String)
    case file(String)
    /// An event, on its day.
    case event(String, start: Int64)
    /// Approvals at one's turn (a review's notification).
    case approvals
    /// No screen of its own on the phone.
    case web(String)

    /// `start`: an event's, which its search result carries.
    public init(path: String, start: Int64? = nil) {
        let parts = URLComponents(string: path)
        let value = { (name: String) in parts?.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        switch parts?.path {
        case "/mail": if let t = value("thread") { self = .thread(t); return }
        case "/chat": if let r = value("room") { self = .room(r); return }
        case "/docs":
            if let d = value("doc") { self = .doc(d); return }
            if value("review") != nil { self = .approvals; return }
        case "/approvals": self = .approvals; return
        case "/calendar": if let e = value("event"), let start { self = .event(e, start: start); return }
        case "/drive":
            if let f = value("folder") { self = .folder(f); return }
            if let f = value("file") { self = .file(f); return }
        default: break
        }
        self = .web(path)
    }

    /// The page on the installation, for a place the phone has no screen
    /// for: only a path on it (never another site a result might name).
    /// The page, signed in: an address with a one-time ticket (it works
    /// once, within a minute, after the person's yes on the page); the
    /// plain page when no ticket can be had.
    public func webAddress(with client: Client) async -> URL? {
        guard let plain = webURL(on: client.server), case let .web(path) = self else { return nil }
        struct Made: Decodable { let url: String }
        guard let made: Made = try? await client.call("POST", "/me/web-ticket", json: ["next": path]), let url = URL(string: made.url) else { return plain }
        return url
    }

    public func webURL(on server: URL) -> URL? {
        guard case let .web(path) = self, path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\") else { return nil }
        return URL(string: server.absoluteString + path)
    }
}

extension Client {
    public func notices() async throws -> [Notice] {
        struct Answer: Decodable { let items: [Notice] }
        let a: Answer = try await call("GET", "/notifications")
        return a.items
    }

    /// How many notifications are unread: the number on the bell, as the
    /// web's bell counts them.
    public func unreadNotices() async throws -> Int {
        struct Answer: Decodable { let unread: Int? }
        let a: Answer = try await call("GET", "/notifications")
        return a.unread ?? 0
    }

    public func markNoticesRead() async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/notifications/read", json: ["all": true])
    }

    public func search(_ words: String) async throws -> [SearchHit] {
        struct Answer: Decodable { let results: [SearchHit] }
        let q = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? ""
        let a: Answer = try await call("GET", "/search?q=\(q)")
        return a.results
    }
}

extension Client {
    /// One file or folder.
    public func item(_ id: String) async throws -> DriveItem {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return try await call("GET", "/drive/items/" + safe)
    }
}
