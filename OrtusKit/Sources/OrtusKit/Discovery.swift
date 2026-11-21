import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Finding an installation from a work email address: the organisation
/// names it at `/.well-known/ortus` (`{"server": "https://…"}`), on its own
/// website or on an `ortus.` host of its domain.
public enum Discovery {
    /// Where to ask, in order, for `name@ministry.gov`.
    public static func candidates(for email: String) -> [URL] {
        let parts = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty else { return [] }
        let domain = String(parts[1])
        guard domain.contains("."), domain.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return [] }
        return ["https://\(domain)/.well-known/ortus", "https://ortus.\(domain)/.well-known/ortus"].compactMap(URL.init(string:))
    }

    /// The installation an answer names, if it names one.
    public static func server(fromAnswer data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = object["server"] as? String,
              let url = Client.serverURL(from: server), url.scheme == "https"
        else { return nil }
        return url
    }

    /// Asks each place in turn; the first answer that names an installation wins.
    public static func find(email: String, session: URLSession = .shared) async -> URL? {
        for url in candidates(for: email) {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let server = server(fromAnswer: data)
            else { continue }
            return server
        }
        return nil
    }
}
