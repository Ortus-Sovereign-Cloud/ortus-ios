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

    public func send(_ request: URLRequest) async throws -> (Int, Data) {
        guard Self.reads(request) else { return try await inner.send(request) }
        let key = Self.key(request)
        if Self.cacheOnly {
            guard let kept = cache.get(key) else { throw URLError(.resourceUnavailable) }
            return (200, kept)
        }
        do {
            let (status, data) = try await inner.send(request)
            if status == 200 { cache.put(key, data) }
            reached(true)
            return (status, data)
        } catch {
            // No connection: what was kept, if anything.
            reached(false)
            if let kept = cache.get(key) { return (200, kept) }
            throw error
        }
    }
}
