// Drive: folders and files, sharing with people and by link.
import Foundation

public struct DriveItem: Decodable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let kind: String
    public let size: Int64?
    public let mime: String?
    public let modifiedAt: Int64?
    public let version: Int64?
    public let label: String?
    public var isFolder: Bool { kind == "folder" }
    public var modified: Date? { modifiedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}

public struct Folder: Decodable {
    public struct Step: Decodable, Equatable { public let id: String; public let name: String }
    public let items: [DriveItem]
    public let path: [Step]
    public let role: String?
}

public struct Shares: Decodable {
    public struct Holder: Decodable, Equatable, Identifiable {
        public let share: String?
        public let email: String?
        public let name: String?
        public let role: String?
        public var id: String { share ?? email ?? name ?? UUID().uuidString }
    }
    public struct Link: Decodable, Equatable {
        public let share: String?
        public let url: String?
        public let expiresAt: Int64?
    }
    public let people: [Holder]?
    public let outside: [Holder]?
    public let link: Link?
}

extension Client {
    public func folder(_ parent: String?) async throws -> Folder {
        try await call("GET", "/drive/items" + (parent.map { "?parent=\($0)" } ?? ""))
    }

    public func shares(_ item: DriveItem) async throws -> Shares {
        try await call("GET", "/drive/items/\(item.id)/shares")
    }

    /// Shares with a colleague (or someone outside, who gets a view link).
    public func share(_ item: DriveItem, with email: String, role: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/drive/items/\(item.id)/shares", json: ["email": email, "role": role])
    }

    /// A view-only link for 30 days (replaces an older one).
    public func makeLink(_ item: DriveItem, days: Int = 30) async throws -> Shares {
        let until = Int64(Date().addingTimeInterval(Double(days) * 86_400).timeIntervalSince1970 * 1000)
        return try await call("POST", "/drive/items/\(item.id)/link", json: ["expiresAt": until])
    }
}
