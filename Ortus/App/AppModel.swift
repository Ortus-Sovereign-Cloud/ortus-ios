import Foundation
import OrtusKit
import SwiftUI

/// Where the app is: joining an installation, enrolling the phone, or in.
@MainActor
final class AppModel: ObservableObject {
    enum Stage { case join, welcome, signedIn }

    @Published var stage: Stage = .join
    @Published var me: Me?
    @Published var error: String?
    @Published var busy = false
    private(set) var client: Client?

    init() {
        // UI tests (and a fresh install) start clean when asked.
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            Keychain.remove("session")
            Keychain.remove("server")
            PhoneKey.forgetAll()
        }
        if let server = lastServer,
           let token = Keychain.get("session").map({ String(decoding: $0, as: UTF8.self) }) {
            client = Client(server: server, token: token)
            stage = .signedIn
            Task { await refresh() }
        }
    }

    /// The installation this phone last used (kept after signing out).
    var lastServer: URL? { Keychain.get("server").flatMap { URL(string: String(decoding: $0, as: UTF8.self)) } }

    /// The phone holds a key of an account on that installation.
    func hasKey(for typed: String) -> Bool {
        Client.serverURL(from: typed).flatMap { PhoneKey.load(for: $0) } != nil
    }

    private func keep(server: URL, token: String) {
        try? Keychain.set(Data(server.absoluteString.utf8), for: "server")
        try? Keychain.set(Data(token.utf8), for: "session")
    }

    func refresh() async {
        guard let client else { return }
        do { me = try await client.call("GET", "/me") } catch let e as APIError where e.status == 401 {
            ended()
        } catch {}
    }

    /// What to tell the person about a failure, in their language: the
    /// installation's own message, or one of the app's.
    func say(_ error: Error) -> String {
        if let e = error as? APIError {
            if e.status > 0, !e.message.isEmpty { return e.message }
            switch e.code {
            case "no_key": return String(localized: "welcome.noKey")
            case "no_session": return String(localized: "join.failed")
            default: return String(localized: "error.generic")
            }
        }
        if error is URLError { return String(localized: "error.network") }
        if let e = error as? LocalizedError, let text = e.errorDescription, error is PhoneKey.NoSecureEnclave { return text }
        return String(localized: "error.generic")
    }

    /// The address a person typed, if the app may talk to it: release
    /// builds talk HTTPS only.
    private func server(from typed: String) -> URL? {
        guard let url = Client.serverURL(from: typed) else { return nil }
        #if DEBUG
        return url
        #else
        return url.scheme == "https" ? url : nil
        #endif
    }

    /// Follows the code from the welcome letter (the invitation) on this
    /// installation: signs in, then the phone becomes the key.
    func join(server typed: String, code: String) async {
        error = nil
        guard let server = server(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = Client(server: server)
        do {
            let token = code.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "#").last ?? ""
            let me: Me = try await client.call("POST", "/invitation/accept", json: ["token": token])
            guard let session = me.session_token else { throw APIError(status: 0, code: "no_session", message: "") }
            client.token = session
            self.client = client
            self.me = me
            keep(server: server, token: session)
            stage = .welcome
        } catch {
            self.error = say(error)
        }
    }

    /// Makes the phone a passkey of the account (Face ID guards it). The
    /// key becomes the phone's only once the installation has taken it.
    func makeKey() async {
        guard let client else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let options: CreationOptions = try await client.call("POST", "/me/passkeys/options")
            let key = try PhoneKey.make()
            let publicURL = client.server.absoluteString
            let rp = try WebAuthn.checkedRPID(options.rp.id, publicURL: publicURL)
            let clientData = WebAuthn.clientData(type: "webauthn.create", challenge: options.challenge, origin: WebAuthn.origin(publicURL: publicURL))
            let auth = WebAuthn.registrationData(rpID: rp, credentialID: key.credentialID, publicKey: key.publicKeyX963)
            let _: [String: String] = try await client.call("POST", "/me/passkeys", json: [
                "name": String(localized: "welcome.keyName"),
                "clientDataJSON": clientData.base64URL,
                "attestationObject": WebAuthn.attestationObject(authData: auth).base64URL,
            ])
            try key.keep(for: client.server)
            // Checked by signing in with it.
            try await signInWithKey(client: client)
            stage = .signedIn
        } catch {
            self.error = say(error)
        }
    }

    /// Signs in with the phone's key (the key alone names the account), and
    /// ends the session it replaces.
    func signInWithKey(client: Client) async throws {
        guard let key = PhoneKey.load(for: client.server) else { throw APIError(status: 0, code: "no_key", message: "") }
        let publicURL = client.server.absoluteString
        let options: RequestOptions = try await client.call("POST", "/session/passkey/options")
        let rp = try WebAuthn.checkedRPID(options.rpId, publicURL: publicURL)
        let clientData = WebAuthn.clientData(type: "webauthn.get", challenge: options.challenge, origin: WebAuthn.origin(publicURL: publicURL))
        let auth = WebAuthn.assertionData(rpID: rp, counter: 0)
        let signature = try key.signature(over: WebAuthn.signedBytes(authData: auth, clientData: clientData))
        var answer: [String: Any] = [
            "id": key.credentialID.base64URL,
            "clientDataJSON": clientData.base64URL,
            "authenticatorData": auth.base64URL,
            "signature": signature.base64URL,
        ]
        if let me { answer["userHandle"] = Data(me.id.utf8).base64URL }
        let signedIn: Me = try await client.call("POST", "/session/passkey", json: answer)
        if let token = signedIn.session_token {
            let old = client.token
            client.token = token
            keep(server: client.server, token: token)
            if let old, old != token { await end(session: old, on: client.server) }
        }
        self.me = signedIn
    }

    /// Back in with the phone's key, after signing out or a session that ended.
    func signInAgain(server typed: String) async {
        error = nil
        guard let server = server(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = Client(server: server)
        do {
            me = nil
            try await signInWithKey(client: client)
            self.client = client
            stage = .signedIn
        } catch {
            self.error = say(error)
        }
    }

    private func end(session token: String, on server: URL) async {
        struct Ignored: Decodable {}
        let _: Ignored? = try? await Client(server: server, token: token).call("POST", "/session/sign-out", json: [:])
    }

    /// The session ended on the server: sign in again (the key stays).
    private func ended() {
        Keychain.remove("session")
        client = nil
        me = nil
        stage = .join
    }

    /// Ends the session on the server too. The key stays: the phone is
    /// still the person's key (an administrator turns off a lost phone's).
    func signOut() async {
        if let client, let token = client.token { await end(session: token, on: client.server) }
        ended()
    }
}
