import Foundation

/// An invitation handed to the app: the installation and the code that
/// lets its person in.
public struct InvitationLink: Equatable, Sendable {
    /// The installation, as its origin (`https://ortus.example`).
    public let server: String
    public let code: String

    public init(server: String, code: String) {
        self.server = server
        self.code = code
    }

    /// Reads the app's own link (`ortus://join?server=…&code=…`, which an
    /// invitation page offers on a phone), the shared app link
    /// (`https://join.ortus.cc/i#s=…&c=…`, in letters and QR codes), an
    /// invitation link (`https://ortus.example/welcome/accept#code`), or nil
    /// for anything else.
    public static func parse(_ text: String) -> InvitationLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "ortus" {
            guard url.host?.lowercased() == "join",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let typed = items.first(where: { $0.name == "server" })?.value,
                  let server = Client.serverURL(from: typed),
                  let code = items.first(where: { $0.name == "code" })?.value, plausible(code)
            else { return nil }
            return InvitationLink(server: server.absoluteString, code: code)
        }
        guard ["http", "https"].contains(scheme), url.host != nil, let fragment = url.fragment else { return nil }
        // The shared app link (https://join.ortus.cc/i#s=…&c=…): the
        // installation and its code after the hash.
        if url.path == "/i" {
            var parts = URLComponents()
            parts.percentEncodedQuery = fragment
            let items = parts.queryItems ?? []
            guard let typed = items.first(where: { $0.name == "s" })?.value,
                  let server = Client.serverURL(from: typed),
                  let code = items.first(where: { $0.name == "c" })?.value, plausible(code)
            else { return nil }
            return InvitationLink(server: server.absoluteString, code: code)
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
