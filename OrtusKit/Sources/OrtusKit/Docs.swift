// A document as the phone reads it: its text now, and its comments.
import Foundation

public struct DocText: Decodable, Equatable {
    public let name: String
    public let now: String
    public let label: String?
}

public struct DocComment: Decodable, Equatable, Identifiable {
    public let id: String
    public let thread: String?
    public let author: String?
    public let body: String
    public let quote: String?
    public let resolved: Bool?
    public let at: Int64?
}

extension Client {
    public func docText(_ doc: String) async throws -> DocText {
        try await call("GET", "/docs/documents/\(doc)/changes")
    }

    public func comments(_ doc: String) async throws -> [DocComment] {
        struct Answer: Decodable { let comments: [DocComment] }
        let a: Answer = try await call("GET", "/docs/documents/\(doc)/comments")
        return a.comments
    }

    public func comment(_ doc: String, body: String) async throws -> [DocComment] {
        struct Answer: Decodable { let comments: [DocComment] }
        let a: Answer = try await call("POST", "/docs/documents/\(doc)/comments", json: ["body": body, "quote": ""])
        return a.comments
    }
}
