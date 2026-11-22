// Mail through JMAP, the way the web client does (/mail/web/jmap with the
// session): the inbox by category, a thread, quick replies, invitations.
import Foundation

public struct Address: Decodable, Equatable, Hashable {
    public let name: String?
    public let email: String?
    public var shown: String { (name?.isEmpty == false ? name : email) ?? "" }
}

public struct Invite: Decodable, Equatable {
    public let uid: String
    public let method: String
    public let summary: String
    public let start: Int64?
    public let end: Int64?
    public let answer: String?
    public let cancelled: Bool
    public let inCalendar: Bool
}

/// How a message one sent is getting to one recipient outside.
public struct Delivery: Decodable, Equatable {
    public let recipient: String?
    /// queued, deferred (trying again), sent (delivered) or bounced.
    public let state: String?
    public let attempts: Int?
    public let lastError: String?
}

public struct Email: Decodable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let subject: String
    public let from: [Address]?
    public let to: [Address]?
    public let replyTo: [Address]?
    public let receivedAt: String
    public let preview: String?
    public let keywords: [String: Bool]?
    public let ortusCategory: String?
    public let ortusInvite: Invite?
    public let ortusText: String?
    public let ortusVerified: Bool?
    public let messageId: [String]?
    public let references: [String]?
    public let hasAttachment: Bool?
    public let ortusDelivery: [Delivery]?

    public var unread: Bool { keywords?["$seen"] != true }
    public var sender: String { from?.first?.shown ?? "" }
    /// Whom it went to (for Sent).
    public var recipients: String { (to ?? []).map(\.shown).joined(separator: ", ") }

    /// The worst delivery state, for a mark in Sent: failed, trying, or nil.
    public var deliveryState: String? {
        guard let d = ortusDelivery, !d.isEmpty else { return nil }
        if d.contains(where: { $0.state == "bounced" }) { return "failed" }
        if d.contains(where: { $0.state == "deferred" }) { return "trying" }
        return nil
    }
    public var date: Date? { ISO8601DateFormatter().date(from: receivedAt) }
}

/// An address one may send from.
public struct Identity: Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let email: String
}

/// Someone to write to, as Compose suggests them.
public struct Suggestion: Decodable, Equatable, Hashable {
    public let name: String?
    public let email: String
    public var shown: String { (name?.isEmpty == false ? name : email) ?? email }
}

public struct Mailbox: Decodable, Equatable {
    public let id: String
    public let name: String
    public let role: String?
    public let unreadEmails: Int?
}

public enum JMAP {
    public static let using = ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission"]
    public static let listProperties = ["threadId", "subject", "from", "to", "receivedAt", "preview", "keywords", "mailboxIds", "hasAttachment", "ortusCategory", "ortusInvite", "ortusDelivery"]
    public static let readProperties = listProperties + ["cc", "replyTo", "messageId", "references", "attachments", "ortusText", "ortusVerified", "ortusDelivery"]

    /// The categories of the inbox.
    public enum Category: String, CaseIterable { case important, other, feeds }

    /// The folders the app shows, by their role.
    public enum Folder: String, CaseIterable { case inbox, sent, archive, trash }

    /// Answers by call id; a method error becomes an APIError.
    static func answers(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responses = root["methodResponses"] as? [[Any]] else {
            throw APIError(status: 0, code: "jmap", message: "Not a JMAP answer.")
        }
        var out: [String: Any] = [:]
        for r in responses where r.count == 3 {
            guard let name = r[0] as? String, let args = r[1] as? [String: Any], let id = r[2] as? String else { continue }
            if name == "error" { throw APIError(status: 0, code: args["type"] as? String ?? "jmap", message: args["description"] as? String ?? "The mail server refused.") }
            if out[id] == nil { out[id] = args }
        }
        return out
    }

    /// Decodes a part of an answer; a list that is missing is empty.
    static func decode<T: Decodable>(_ value: Any?, as: T.Type = T.self) throws -> T {
        guard let value, !(value is NSNull) else {
            return try JSONDecoder().decode(T.self, from: Data("[]".utf8))
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Client {
    /// Runs JMAP method calls.
    public func jmap(_ calls: [[Any]]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["using": JMAP.using, "methodCalls": calls], options: [.sortedKeys])
        let (status, data) = try await transport.send(request("POST", "/mail/web/jmap", body: body))
        guard (200..<300).contains(status) else { throw APIError(status: status, code: "http_\(status)", message: "") }
        return try JMAP.answers(data)
    }

    /// The inbox in one category, newest first (threads collapsed), with
    /// the mailboxes and how many are unread in each category.
    public func inbox(_ category: JMAP.Category) async throws -> (emails: [Email], unread: [JMAP.Category: Int], mailboxes: [Mailbox]) {
        let boxes = try JMAP.decode(try await jmap([["Mailbox/get", [:], "b"]])["b"].flatMap { ($0 as? [String: Any])?["list"] }, as: [Mailbox].self)
        guard let inbox = boxes.first(where: { $0.role == "inbox" }) else { return ([], [:], boxes) }
        var calls: [[Any]] = [
            ["Email/query", ["filter": ["operator": "AND", "conditions": [["inMailbox": inbox.id], ["ortusCategory": category.rawValue]]], "sort": [["property": "receivedAt", "isAscending": false]], "collapseThreads": true, "limit": 100], "q"],
            ["Email/get", ["#ids": ["resultOf": "q", "name": "Email/query", "path": "/ids"], "properties": JMAP.listProperties], "l"],
        ]
        for c in JMAP.Category.allCases {
            calls.append(["Email/query", ["filter": ["operator": "AND", "conditions": [["inMailbox": inbox.id], ["ortusCategory": c.rawValue], ["notKeyword": "$seen"]]], "calculateTotal": true, "limit": 0], "u-\(c.rawValue)"])
        }
        let got = try await jmap(calls)
        let emails = try JMAP.decode((got["l"] as? [String: Any])?["list"], as: [Email].self)
        var unread: [JMAP.Category: Int] = [:]
        for c in JMAP.Category.allCases { unread[c] = (got["u-\(c.rawValue)"] as? [String: Any])?["total"] as? Int ?? 0 }
        return (emails, unread, boxes)
    }

    /// A folder other than the inbox, newest first (threads collapsed).
    public func folder(_ folder: JMAP.Folder) async throws -> [Email] {
        let boxes = try JMAP.decode(try await jmap([["Mailbox/get", [:], "b"]])["b"].flatMap { ($0 as? [String: Any])?["list"] }, as: [Mailbox].self)
        guard let box = boxes.first(where: { $0.role == folder.rawValue }) else { return [] }
        let got = try await jmap([
            ["Email/query", ["filter": ["inMailbox": box.id], "sort": [["property": "receivedAt", "isAscending": false]], "collapseThreads": true, "limit": 100], "q"],
            ["Email/get", ["#ids": ["resultOf": "q", "name": "Email/query", "path": "/ids"], "properties": JMAP.listProperties], "l"],
        ])
        return try JMAP.decode((got["l"] as? [String: Any])?["list"], as: [Email].self)
    }

    /// The messages of a thread, oldest first.
    public func thread(_ id: String) async throws -> [Email] {
        let got = try await jmap([
            ["Thread/get", ["ids": [id]], "t"],
            ["Email/get", ["#ids": ["resultOf": "t", "name": "Thread/get", "path": "/list/*/emailIds"], "properties": JMAP.readProperties], "e"],
        ])
        return try JMAP.decode((got["e"] as? [String: Any])?["list"], as: [Email].self)
    }

    /// Marks messages read.
    public func markRead(_ ids: [String]) async throws {
        var update: [String: Any] = [:]
        for id in ids { update[id] = ["keywords/$seen": true] }
        _ = try await jmap([["Email/set", ["update": update], "r"]])
    }

    /// Replies to the last message of a thread with plain text.
    public func reply(to last: Email, text: String) async throws {
        let got = try await jmap([["Identity/get", [:], "i"], ["Mailbox/get", [:], "b"]])
        guard let identity = ((got["i"] as? [String: Any])?["list"] as? [[String: Any]])?.first,
              let identityID = identity["id"] as? String,
              let drafts = ((got["b"] as? [String: Any])?["list"] as? [[String: Any]])?.first(where: { $0["role"] as? String == "drafts" })?["id"] as? String else {
            throw APIError(status: 0, code: "forbiddenFrom", message: "You cannot send from here.")
        }
        let to = (last.replyTo?.isEmpty == false ? last.replyTo : last.from) ?? []
        let subject = last.subject.lowercased().hasPrefix("re:") ? last.subject : "Re: \(last.subject)"
        let draft: [String: Any] = [
            "mailboxIds": [drafts: true],
            "keywords": ["$draft": true, "$seen": true],
            "from": [["name": identity["name"] ?? "", "email": identity["email"] ?? ""]],
            "to": to.map { ["name": $0.name ?? "", "email": $0.email ?? ""] },
            "subject": subject,
            "inReplyTo": last.messageId ?? NSNull(),
            "references": (last.references ?? []) + (last.messageId ?? []),
            "textBody": [["partId": "1", "type": "text/plain"]],
            "bodyValues": ["1": ["value": text]],
        ]
        let sent = try await jmap([
            ["Email/set", ["create": ["r": draft]], "c"],
            ["EmailSubmission/set", ["create": ["s": ["identityId": identityID, "emailId": "#r"]], "onSuccessDestroyEmail": ["#s"]], "s"],
        ])
        if let failed = ((sent["s"] as? [String: Any])?["notCreated"] as? [String: Any])?["s"] as? [String: Any] {
            throw APIError(status: 0, code: failed["type"] as? String ?? "notSent", message: failed["description"] as? String ?? "Not sent.")
        }
    }

    /// The addresses one may send from (none: no mail address here).
    public func identities() async throws -> [Identity] {
        let got = try await jmap([["Identity/get", [:], "i"]])
        return try JMAP.decode((got["i"] as? [String: Any])?["list"], as: [Identity].self)
    }

    /// People to write to whose name or address starts with `query`.
    public func suggest(_ query: String) async throws -> [Suggestion] {
        struct Found: Decodable { let people: [Suggestion] }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let (status, data) = try await transport.send(request("GET", "/mail/people?q=\(q)"))
        guard (200..<300).contains(status) else { throw APIError(status: status, code: "http_\(status)", message: "") }
        return try JSONDecoder().decode(Found.self, from: data).people
    }

    /// Sends a new message from `identity` to `to`.
    public func send(from identity: Identity, to: [String], subject: String, text: String) async throws {
        let got = try await jmap([["Mailbox/get", [:], "b"]])
        guard let drafts = ((got["b"] as? [String: Any])?["list"] as? [[String: Any]])?.first(where: { $0["role"] as? String == "drafts" })?["id"] as? String else {
            throw APIError(status: 0, code: "notSent", message: "Not sent.")
        }
        let draft: [String: Any] = [
            "mailboxIds": [drafts: true],
            "keywords": ["$draft": true, "$seen": true],
            "from": [["name": identity.name ?? "", "email": identity.email]],
            "to": to.map { ["email": $0] },
            "subject": subject,
            "textBody": [["partId": "1", "type": "text/plain"]],
            "bodyValues": ["1": ["value": text]],
        ]
        let sent = try await jmap([
            ["Email/set", ["create": ["m": draft]], "c"],
            ["EmailSubmission/set", ["create": ["s": ["identityId": identity.id, "emailId": "#m"]], "onSuccessDestroyEmail": ["#s"]], "s"],
        ])
        if let failed = ((sent["c"] as? [String: Any])?["notCreated"] as? [String: Any])?["m"] as? [String: Any] {
            throw APIError(status: 0, code: failed["type"] as? String ?? "notSent", message: failed["description"] as? String ?? "Not sent.")
        }
        if let failed = ((sent["s"] as? [String: Any])?["notCreated"] as? [String: Any])?["s"] as? [String: Any] {
            throw APIError(status: 0, code: failed["type"] as? String ?? "notSent", message: failed["description"] as? String ?? "Not sent.")
        }
    }

    /// Answers the invitation in a message: accepted, tentative or declined.
    public func rsvp(_ email: Email, answer: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/mail/messages/\(email.id)/rsvp", json: ["answer": answer])
    }
}
