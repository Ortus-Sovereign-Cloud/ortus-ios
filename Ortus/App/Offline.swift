import Foundation
import OrtusKit

extension AppModel {
    /// The answers this phone keeps for an installation (in Caches: never
    /// backed up, readable after the phone's first unlock).
    nonisolated static func cache(for server: URL) -> ResponseCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let name = SHA256.hash(Data(server.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return ResponseCache(directory: base.appendingPathComponent("ortus-" + name, isDirectory: true))
    }

    /// A client whose reads are kept, and answered from the phone when the
    /// installation cannot be reached (the app then says it is offline).
    func makeClient(_ server: URL, token: String? = nil) -> Client {
        let transport = CachingTransport(cache: Self.cache(for: server)) { [weak self] reached in
            Task { @MainActor in
                if self?.offline != !reached { self?.offline = !reached }
            }
        }
        return Client(server: server, token: token, transport: transport)
    }

    /// Signing out, or another account: nothing of the last one stays.
    func forgetKept(_ server: URL) {
        Self.cache(for: server).clear()
    }
}

/// Shows what the phone kept at once, then what the installation says.
@MainActor
func quickly<T>(_ load: @escaping () async throws -> T, show: (T) -> Void) async throws {
    if let kept = try? await CachingTransport.$cacheOnly.withValue(true, operation: { try await load() }) {
        show(kept)
    }
    show(try await load())
}
