// What an administrator does from the phone: mailbox imports that failed,
// inviting someone.
import Foundation

public struct ImportAccount: Decodable, Equatable, Identifiable {
    public let id: String
    public let login: String
    public let target: String
    public let state: String
    public let error: String?
    public let copied: Int64
    public var failed: Bool { state == "failed" }
}

public struct MailImport: Decodable, Equatable, Identifiable {
    public let id: String
    public let host: String
    public let accounts: [ImportAccount]
}

extension Client {
    public func imports() async throws -> [MailImport] {
        struct Answer: Decodable { let imports: [MailImport] }
        let a: Answer = try await call("GET", "/mail/admin/imports")
        return a.imports
    }

    /// Tries a failed account again with the password its owner gave.
    public func retry(_ account: ImportAccount, password: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/mail/admin/imports/accounts/\(account.id)/retry", json: ["password": password])
    }

    /// Asks the owners of failed accounts for their old password (a
    /// message with a link in each one's inbox).
    public func askOwners(_ accounts: [ImportAccount]) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/mail/admin/imports/ask-owners", json: ["accounts": accounts.map(\.id)])
    }

    public func invite(name: String, email: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/admin/users", json: ["name": name, "email": email])
    }
}
