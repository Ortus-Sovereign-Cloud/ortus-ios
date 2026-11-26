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

/// JSON as it came, kept to be handed on whole (a sealed message's body).
public indirect enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public struct ChatMessage: Decodable, Equatable, Identifiable {
    public let id: String
    public let seq: Int64?
    public let sender: String
    /// Empty in an end-to-end room: `sealed` holds the message for the phone's keys.
    public let text: String
    public let at: Int64
    public let thread: String?
    public let deleted: Bool?
    public let sealed: JSONValue?
    /// How many replies its thread has (a room's messages only).
    public let replies: Int?
    public var date: Date { Date(timeIntervalSince1970: Double(at) / 1000) }

    /// The message as the end-to-end library opens it: id, sender, thread and sealed.
    public func sealedJSON() -> String {
        var o: [String: JSONValue] = ["id": .string(id), "sender": .string(sender)]
        if let thread { o["thread"] = .string(thread) }
        if let sealed { o["sealed"] = sealed }
        let data = (try? JSONEncoder().encode(JSONValue.object(o))) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Refused before anything leaves the phone: an end-to-end room's messages are sealed on it.
public struct SealedRoom: Error, Equatable {
    public let room: String
}

public struct Messages: Decodable {
    public let messages: [ChatMessage]
    public let people: [String: Person]
}

extension Client {
    /// The rooms; the end-to-end ones are remembered, and never get a message in the clear.
    public func rooms() async throws -> Rooms {
        let r: Rooms = try await call("GET", "/chat/rooms")
        markSealed(r.rooms.filter { $0.encrypted == true }.map(\.id))
        return r
    }

    /// A room's latest messages, or one thread's (its root and replies).
    public func messages(in room: String, thread: String? = nil) async throws -> Messages {
        let query = thread.map { "?thread=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? ""
        return try await call("GET", "/chat/rooms/\(room)/messages" + query)
    }

    public func say(_ text: String, in room: String, thread: String? = nil) async throws {
        if isSealed(room) { throw SealedRoom(room: room) }
        struct Sent: Decodable { let id: String? }
        // Its client id makes a resend from the outbox one message.
        var body: [String: Any] = ["text": text, "client_id": UUID().uuidString]
        if let thread { body["thread"] = thread }
        let _: Sent = try await call("POST", "/chat/rooms/\(room)/messages", json: body)
    }
}
