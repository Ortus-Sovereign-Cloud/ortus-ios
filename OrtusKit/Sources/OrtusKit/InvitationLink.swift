import Foundation

/// A link handed to the app: the installation and the code that lets its
/// person in, an invitation's or a phone sign-in code's.
public struct InvitationLink: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An invitation: the account becomes active.
        case invite
        /// "Sign in on your phone" from the web: signs in as its person.
        case phone
    }

    /// The installation, as its origin (`https://ortus.example`).
    public let server: String
    public let code: String
    public let kind: Kind

    public init(server: String, code: String, kind: Kind = .invite) {
        self.server = server
        self.code = code
        self.kind = kind
    }

    /// Reads the app's own link (`ortus://join?server=…&code=…`, which an
    /// invitation page offers on a phone; `ortus://signin?…` for a phone
    /// sign-in code), the shared app link (`https://join.ortus.cc/i#s=…&c=…`,
    /// in letters and QR codes; `&p=…` for a phone sign-in code), an
    /// invitation link (`https://ortus.example/welcome/accept#code`), or nil
    /// for anything else.
    public static func parse(_ text: String) -> InvitationLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "ortus" {
            let host = url.host?.lowercased()
            guard host == "join" || host == "signin",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let typed = items.first(where: { $0.name == "server" })?.value,
                  let server = Client.serverURL(from: typed),
                  let code = items.first(where: { $0.name == "code" })?.value, plausible(code)
            else { return nil }
            return InvitationLink(server: server.absoluteString, code: code, kind: host == "signin" ? .phone : .invite)
        }
        guard ["http", "https"].contains(scheme), url.host != nil, let fragment = url.fragment else { return nil }
        // The shared app link (https://join.ortus.cc/i#s=…&c=…): the
        // installation and its code after the hash.
        if url.path == "/i" {
            var parts = URLComponents()
            parts.percentEncodedQuery = fragment
            let items = parts.queryItems ?? []
            let phone = items.contains(where: { $0.name == "p" })
            guard let typed = items.first(where: { $0.name == "s" })?.value,
                  let server = Client.serverURL(from: typed),
                  let code = items.first(where: { $0.name == (phone ? "p" : "c") })?.value, plausible(code)
            else { return nil }
            return InvitationLink(server: server.absoluteString, code: code, kind: phone ? .phone : .invite)
        }
        guard url.path == "/welcome/accept", plausible(fragment) else { return nil }
        return InvitationLink(server: WebAuthn.origin(publicURL: trimmed), code: fragment)
    }

    /// Codes are base64url, long enough to be secret.
    private static func plausible(_ code: String) -> Bool {
        code.count >= 16 && code.count <= 200
            && code.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" }
    }
}
