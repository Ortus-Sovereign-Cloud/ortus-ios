// Chat rooms and messages, as the web client reads them.
import Foundation

public struct Person: Decodable, Equatable {
    public let name: String
    public let email: String?
    public let local: Bool?
}

public struct Room: Decodable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let kind: String
    public let topic: String?
    public let unread: Int?
    public let state: String?
    public let federated: Bool?
    public let encrypted: Bool?
    public let with: [String]?

    public static func == (a: Room, b: Room) -> Bool { a.id == b.id && a.unread == b.unread && a.name == b.name }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct Rooms: Decodable {
    public let rooms: [Room]
    public let people: [String: Person]
    public let me: String?

    /// What a room is called: a channel by its name, a direct message by
    /// the other person.
    public func title(_ room: Room) -> String {
        if room.kind == "direct", let other = room.with?.first { return people[other]?.name ?? other }
        return room.kind == "channel" ? "# \(room.name)" : room.name
    }
}

public struct ChatMessage: Decodable, Equatable, Identifiable {
    public let id: String
    public let seq: Int64?
    public let sender: String
    public let text: String
    public let at: Int64
    public let thread: String?
    public let deleted: Bool?
    public var date: Date { Date(timeIntervalSince1970: Double(at) / 1000) }
}

public struct Messages: Decodable {
    public let messages: [ChatMessage]
    public let people: [String: Person]
}

extension Client {
    public func rooms() async throws -> Rooms { try await call("GET", "/chat/rooms") }

    public func messages(in room: String) async throws -> Messages {
        try await call("GET", "/chat/rooms/\(room)/messages")
    }

    public func say(_ text: String, in room: String) async throws {
        struct Sent: Decodable { let id: String? }
        // Its client id makes a resend from the outbox one message.
        let _: Sent = try await call("POST", "/chat/rooms/\(room)/messages", json: ["text": text, "client_id": UUID().uuidString])
    }
}
