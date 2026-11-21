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
    public let app: String
    public let id: String
    public let title: String
    public let snippet: String?
    public let at: Int64?
    public var key: String { app + ":" + id }
}

extension Client {
    public func notices() async throws -> [Notice] {
        struct Answer: Decodable { let items: [Notice] }
        let a: Answer = try await call("GET", "/notifications")
        return a.items
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
