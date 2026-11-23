// Reading without a connection: the last answer to every read (a GET, or a
// JMAP request made only of gets and queries) is kept on the phone, served
// when the installation cannot be reached, and shown first so screens open
// at once. Writes always need the connection.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where answers are kept: one file each, in a directory of their own.
public final class ResponseCache: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".json") }

    public func get(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return try? Data(contentsOf: file(key))
    }

    public func put(_ key: String, _ data: Data) {
        lock.lock(); defer { lock.unlock() }
        try? data.write(to: file(key), options: [.atomic])
    }

    /// Everything kept (signing out, another account).
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        for f in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

/// Messages written without a connection, kept on the phone (without the
/// session: the one in use is added when they go) and sent in order once
/// the installation answers again.
public final class Outbox: @unchecked Sendable {
    struct Item: Codable { let id: String; let method: String; let url: String; let body: Data? }
    private let file: URL
    private let lock = NSLock()
    private var sending = false
    /// Told how many wait.
    public var changed: @Sendable (Int) -> Void = { _ in }

    public init(file: URL) {
        self.file = file
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func items() -> [Item] { (try? JSONDecoder().decode([Item].self, from: Data(contentsOf: file))) ?? [] }
    private func save(_ list: [Item]) { try? JSONEncoder().encode(list).write(to: file, options: [.atomic]) }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return items().count }

    func add(_ r: URLRequest) {
        lock.lock()
        var list = items()
        list.append(Item(id: UUID().uuidString, method: r.httpMethod ?? "POST", url: r.url?.absoluteString ?? "", body: r.httpBody))
        save(list)
        lock.unlock()
        changed(list.count)
    }

    public func clear() {
        lock.lock(); try? FileManager.default.removeItem(at: file); lock.unlock()
        changed(0)
    }

    /// Sends what waits, oldest first, with `authorization`; stops at the
    /// first that cannot go yet. A message the installation refuses (4xx)
    /// is dropped, not retried forever.
    func flush(with inner: Transport, authorization: String?) async {
        lock.lock()
        if sending || items().isEmpty { lock.unlock(); return }
        sending = true
        lock.unlock()
        defer { lock.lock(); sending = false; lock.unlock() }
        while true {
            lock.lock(); let next = items().first; lock.unlock()
            guard let next, let url = URL(string: next.url) else { return }
            var r = URLRequest(url: url)
            r.httpMethod = next.method
            r.httpBody = next.body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.setValue("ortus", forHTTPHeaderField: "X-Requested-With")
            if let authorization { r.setValue(authorization, forHTTPHeaderField: "Authorization") }
            guard let (status, _) = try? await inner.send(r), status < 500 else { return }
            lock.lock()
            let rest = items().filter { $0.id != next.id }
            save(rest)
            lock.unlock()
            changed(rest.count)
        }
    }
}

/// A transport that keeps reads and answers them from the phone when the
/// installation cannot be reached.
public final class CachingTransport: Transport, @unchecked Sendable {
    /// Answer reads from the phone only (to show what was kept at once).
    @TaskLocal public static var cacheOnly = false

    let inner: Transport
    public let cache: ResponseCache
    /// Told whether the last read reached the installation.
    let reached: @Sendable (Bool) -> Void

    public init(inner: Transport = URLSessionTransport(), cache: ResponseCache, reached: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.inner = inner
        self.cache = cache
        self.reached = reached
    }

    /// Whether a request only reads.
    private func flush(after request: URLRequest) {
        guard let outbox, outbox.count > 0 else { return }
        let auth = request.value(forHTTPHeaderField: "Authorization")
        let inner = inner
        Task { await outbox.flush(with: inner, authorization: auth) }
    }

    public static func reads(_ r: URLRequest) -> Bool {
        let path = r.url?.path ?? ""
        if r.httpMethod == "GET" || r.httpMethod == nil { return !path.contains("/push/") && !path.contains("/session") }
        guard r.httpMethod == "POST", path.hasSuffix("/jmap"), let body = r.httpBody,
              let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let calls = root["methodCalls"] as? [[Any]], !calls.isEmpty else { return false }
        return calls.allSatisfy { ($0.first as? String).map { $0.hasSuffix("/get") || $0.hasSuffix("/query") } ?? false }
    }

    static func key(_ r: URLRequest) -> String {
        var text = (r.httpMethod ?? "GET") + " " + (r.url?.absoluteString ?? "")
        if let body = r.httpBody { text += "\n" + String(decoding: body, as: UTF8.self) }
        return SHA256.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes that wait for the connection (mail and chat messages).
    public var outbox: Outbox?

    /// A message to send: chat messages and mail submissions.
    public static func queueable(_ r: URLRequest) -> Bool {
        let path = r.url?.path ?? ""
        guard r.httpMethod == "POST" else { return false }
        if path.contains("/chat/rooms/"), path.hasSuffix("/messages") { return true }
        if path.hasSuffix("/jmap"), let body = r.httpBody, String(decoding: body, as: UTF8.self).contains("EmailSubmission/set") { return true }
        return false
    }

    /// The request certainly never left the phone (so sending it later cannot send it twice).
    static func neverLeft(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(e.code)
    }

    public func send(_ request: URLRequest) async throws -> (Int, Data) {
        guard Self.reads(request) else {
            do {
                let answer = try await inner.send(request)
                reached(true)
                flush(after: request)
                return answer
            } catch {
                if let outbox, Self.queueable(request), Self.neverLeft(error) {
                    outbox.add(request)
                    reached(false)
                    throw APIError(status: 0, code: "queued", message: "")
                }
                throw error
            }
        }
        let key = Self.key(request)
        if Self.cacheOnly {
            guard let kept = cache.get(key) else { throw URLError(.resourceUnavailable) }
            return (200, kept)
        }
        do {
            let (status, data) = try await inner.send(request)
            if status == 200 { cache.put(key, data) }
            reached(true)
            flush(after: request)
            return (status, data)
        } catch {
            // No connection: what was kept, if anything.
            reached(false)
            if let kept = cache.get(key) { return (200, kept) }
            throw error
        }
    }
}
