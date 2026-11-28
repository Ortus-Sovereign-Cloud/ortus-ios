// A call as the phone has it natively: the same media node and signalling
// as the web client. Join; one connection with a data channel named
// "signalling" and three send-only transceivers (audio, camera, screen);
// the offer goes to /offer; the node's later offers (others' tracks) come
// over the data channel in parts and are answered there; a state report
// every 10 s keeps the session; leave.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct IceServer: Decodable, Equatable, Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?
}

public struct CallSession: Decodable, Equatable, Sendable {
    public let session: String
    public let user: String
    public let muted: Bool?
    public let camera: Bool?
    /// The mid of the video they share, when they share one.
    public let screen: String?

    public init(session: String, user: String, muted: Bool? = nil, camera: Bool? = nil, screen: String? = nil) {
        (self.session, self.user, self.muted, self.camera, self.screen) = (session, user, muted, camera, screen)
    }
}

public struct CallInfo: Decodable, Equatable, Sendable {
    public struct Person: Decodable, Equatable, Sendable { public let name: String }
    public let id: String
    public let room: String
    public let sessions: [CallSession]
    public let people: [String: Person]

    /// The name of whoever a session (a remote stream's id) belongs to.
    public func name(of session: String) -> String? {
        sessions.first { $0.session == session }.flatMap { people[$0.user]?.name }
    }

    /// Of a session's video tracks (by the sender's mid, as the node names
    /// them), the camera's: never the screen's, and else the first mid
    /// (every client adds its camera before its screen).
    public func camera(of session: String, mids: some Collection<String>) -> String? {
        let screen = sessions.first { $0.session == session }?.screen
        return Self.first(mids.filter { $0 != screen })
    }

    /// The lowest mid, by number.
    public static func first(_ mids: some Collection<String>) -> String? {
        mids.min { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
    }
}

public struct Joined: Decodable, Equatable, Sendable {
    public let call: CallInfo
    public let session: String
    public let ice_servers: [IceServer]?
}

extension Client {
    private func safe(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }

    public func joinCall(room: String) async throws -> Joined {
        try await call("POST", "/calls/rooms/\(safe(room))/join", json: [:])
    }

    /// Sends the connection's offer; gives the node's answer (SDP).
    public func sendOffer(session: String, sdp: String) async throws -> String {
        struct Answer: Decodable { struct D: Decodable { let sdp: String }; let answer: D }
        let a: Answer = try await call("POST", "/calls/sessions/\(safe(session))/offer", json: ["offer": ["type": "offer", "sdp": sdp]])
        return a.answer.sdp
    }

    /// Reports muted and camera (and keeps the session); gives the call now.
    public func callState(session: String, muted: Bool, camera: Bool) async throws -> CallInfo {
        struct Answer: Decodable { let call: CallInfo }
        let a: Answer = try await call("POST", "/calls/sessions/\(safe(session))/state", json: ["muted": muted, "camera": camera])
        return a.call
    }

    public func leaveCall(session: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/calls/sessions/\(safe(session))/leave", json: [:])
    }
}

/// Session descriptions over the data channel, in parts of at most 16 KB.
public enum CallParts {
    static let size = 16 * 1024

    public static func split(_ text: String, id: String = String(UUID().uuidString.prefix(8))) -> [String] {
        let chars = Array(text)
        let of = max(1, (chars.count + size - 1) / size)
        return (0..<of).map { i in
            let data = String(chars[(i * size)..<min(chars.count, (i + 1) * size)])
            let o: [String: Any] = ["id": id, "part": i, "of": of, "data": data]
            return String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
        }
    }

    /// Puts parts back together; gives the whole message once it is complete.
    public final class Joiner {
        private var id: String?
        private var got: [String?] = []
        public init() {}

        public func take(_ raw: String) -> String? {
            guard let o = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let id = o["id"] as? String, let part = o["part"] as? Int, let of = o["of"] as? Int, let data = o["data"] as? String,
                  of >= 1, of <= 64, part >= 0, part < of else { return nil }
            if self.id != id || got.count != of { self.id = id; got = Array(repeating: nil, count: of) }
            got[part] = data
            guard got.allSatisfy({ $0 != nil }) else { return nil }
            let whole = got.compactMap { $0 }.joined()
            self.id = nil
            got = []
            return whole
        }
    }

    /// A node's offer: its SDP and number, if it is one.
    public static func offer(_ message: String) -> (sdp: String, n: Int?)? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              o["type"] as? String == "offer", let sdp = o["sdp"] as? String else { return nil }
        return (sdp, o["n"] as? Int)
    }

    /// Our answer to the node's offer number `n`.
    public static func answer(_ sdp: String, n: Int?) -> String {
        var o: [String: Any] = ["type": "answer", "sdp": sdp]
        if let n { o["n"] = n }
        return String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), as: UTF8.self)
    }
}
