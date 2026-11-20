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

    public var unread: Bool { keywords?["$seen"] != true }
    public var sender: String { from?.first?.shown ?? "" }
    public var date: Date? { ISO8601DateFormatter().date(from: receivedAt) }
}

public struct Mailbox: Decodable, Equatable {
    public let id: String
    public let name: String
    public let role: String?
    public let unreadEmails: Int?
}

public enum JMAP {
    public static let using = ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail", "urn:ietf:params:jmap:submission"]
    public static let listProperties = ["threadId", "subject", "from", "to", "receivedAt", "preview", "keywords", "mailboxIds", "hasAttachment", "ortusCategory", "ortusInvite"]
    public static let readProperties = listProperties + ["cc", "replyTo", "messageId", "references", "attachments", "ortusText", "ortusVerified"]

    /// The categories of the inbox.
    public enum Category: String, CaseIterable { case important, other, feeds }

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
        let body = try JSONSerialization.data(withJSONObject: ["using": JMAP.using, "methodCalls": calls])
        let (status, data) = try await transport.send(request("POST", "/mail/web/jmap", body: body))
        guard (200..<300).contains(status) else { throw APIError(status: status, code: "http_\(status)", message: "The server answered \(status).") }
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

    /// Answers the invitation in a message: accepted, tentative or declined.
    public func rsvp(_ email: Email, answer: String) async throws {
        let _: [String: String?] = try await call("POST", "/mail/messages/\(email.id)/rsvp", json: ["answer": answer])
    }
}
