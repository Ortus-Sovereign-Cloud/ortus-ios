// End-to-end rooms on this phone, through ortus-chat's phones/e2e library
// (the OrtusE2E module): this device's keys in a store of its own in
// Application Support (protected until the first unlock, not backed up),
// encrypted with a random passphrase kept in the Keychain (after the first
// unlock, this device only).
//
// Every call blocks while it talks to the server, so all of them run on one
// queue of their own, never on the main thread or Swift's shared pool.
//
// The store, its passphrase and the device id belong together: when the
// store cannot be opened (a restored phone, a lost Keychain item), this
// phone becomes a new device, as an old id with new keys would be refused.
import Foundation
import OrtusE2E
import OrtusKit
import Security

final class EndToEnd: @unchecked Sendable {
    private let client: Client
    private let queue = DispatchQueue(label: "cc.ortus.e2e")
    private var library: OrtusE2e?
    /// What was opened, by message id: opening a message again is not needed.
    private var opened: [String: String] = [:]

    init(client: Client) { self.client = client }

    /// The phone's keys cannot be made or read: the room is for a computer.
    static func unavailable(_ error: Error) -> Bool {
        if case E2eError.Store = error { return true }
        return false
    }

    /// The library's HTTP, signed in as the person: never answered from the
    /// phone's cache nor queued offline. Called on the e2e queue (blocking).
    private final class HTTP: OrtusE2E.Transport, @unchecked Sendable {
        /// As the kit's: no cookies, no disk cache (the session lives in the Keychain).
        static let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = nil
            return URLSession(configuration: config)
        }()
        let client: Client
        init(client: Client) { self.client = client }

        func http(method: String, path: String, body: String?) throws -> HttpResponse {
            let request = client.request(method, path, body: body.map { Data($0.utf8) })
            let done = DispatchSemaphore(value: 0)
            var answer: Result<HttpResponse, Error> = .failure(TransportError.Failed(detail: "no answer"))
            let task = Self.session.dataTask(with: request) { data, response, error in
                if let error {
                    answer = .failure(TransportError.Failed(detail: error.localizedDescription))
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    answer = .success(HttpResponse(status: UInt16(clamping: status), body: String(decoding: data ?? Data(), as: UTF8.self)))
                }
                done.signal()
            }
            task.resume()
            done.wait()
            return try answer.get()
        }
    }

    private static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// A device id: letters and digits, as the server takes them.
    private static func newDevice() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "PHONE" + String((0..<10).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }

    /// `@{user}:{serverName}`, as `me` of the rooms says.
    private static func parse(_ me: String) throws -> (user: String, server: String) {
        let at = me.hasPrefix("@") ? String(me.dropFirst()) : me
        guard let colon = at.firstIndex(of: ":"), colon != at.startIndex else { throw E2eError.Invalid(detail: "not a Matrix id: \(me)") }
        return (String(at[..<colon]), String(at[at.index(after: colon)...]))
    }

    private static func directory(_ user: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("e2e", isDirectory: true).appendingPathComponent(user, isDirectory: true)
    }

    private func begin(_ dir: URL, user: String) throws -> (device: String, passphrase: String) {
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = dir
        try marked.setResourceValues(values)
        let made = (Self.newDevice(), Self.random())
        try Keychain.set(Data(made.0.utf8), for: "e2e.device.\(user)")
        try Keychain.set(Data(made.1.utf8), for: "e2e.passphrase.\(user)")
        return made
    }

    private func open(_ me: String) throws -> OrtusE2e {
        if let library { return library }
        let (user, server) = try Self.parse(me)
        let dir = try Self.directory(user)
        let keptDevice = Keychain.get("e2e.device.\(user)").map { String(decoding: $0, as: UTF8.self) }
        let keptPass = Keychain.get("e2e.passphrase.\(user)").map { String(decoding: $0, as: UTF8.self) }
        var device: String
        var pass: String
        if let keptDevice, let keptPass, FileManager.default.fileExists(atPath: dir.path) {
            device = keptDevice
            pass = keptPass
        } else {
            let made = try begin(dir, user: user)
            device = made.device
            pass = made.passphrase
        }
        let made: OrtusE2e
        do {
            made = try OrtusE2e.open(storeDir: dir.path, passphrase: pass, user: user, device: device, serverName: server, transport: HTTP(client: client))
        } catch E2eError.Store(_) {
            // The keys cannot be read: a new device.
            let fresh = try begin(dir, user: user)
            device = fresh.device
            pass = fresh.passphrase
            made = try OrtusE2e.open(storeDir: dir.path, passphrase: pass, user: user, device: device, serverName: server, transport: HTTP(client: client))
        }
        library = made
        return made
    }

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { done in
            queue.async { done.resume(with: Result { try work() }) }
        }
    }

    /// Each message's text, or nil when it cannot be opened (a room key that
    /// has not come, a sender refused). Room keys waiting are taken in first.
    func read(me: String, room: String, messages: [ChatMessage]) async throws -> [String: String?] {
        try await run {
            let e2e = try self.open(me)
            _ = try? e2e.inbox()
            var out: [String: String?] = [:]
            for m in messages {
                if let known = self.opened[m.id] { out[m.id] = known; continue }
                guard m.sealed != nil, let text = try? e2e.decrypt(room: room, messageJson: m.sealedJSON()).text else { out[m.id] = .some(nil); continue }
                self.opened[m.id] = text
                out[m.id] = text
            }
            return out
        }
    }

    /// Seals and sends: the message's id.
    func send(me: String, room: String, text: String) async throws -> String {
        try await run { try self.open(me).send(room: room, text: text, thread: nil) }
    }

    /// Signing out: the server drops this device, the phone its keys.
    func forget(me: String?) async {
        _ = try? await run {
            guard let me, let user = try? Self.parse(me).user else { return }
            if self.library == nil, Keychain.get("e2e.device.\(user)") != nil { _ = try? self.open(me) }
            try? self.library?.forget()
            self.library = nil
            self.opened = [:]
            if let dir = try? Self.directory(user) { try? FileManager.default.removeItem(at: dir) }
            Keychain.remove("e2e.device.\(user)")
            Keychain.remove("e2e.passphrase.\(user)")
        }
    }
}
