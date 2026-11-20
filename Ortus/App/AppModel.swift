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
            Keychain.remove("phone-key")
        }
        if let server = Keychain.get("server").flatMap({ URL(string: String(decoding: $0, as: UTF8.self)) }),
           let token = Keychain.get("session").map({ String(decoding: $0, as: UTF8.self) }) {
            client = Client(server: server, token: token)
            stage = .signedIn
            Task { await refresh() }
        }
    }

    private func keep(server: URL, token: String) {
        Keychain.set(Data(server.absoluteString.utf8), for: "server")
        Keychain.set(Data(token.utf8), for: "session")
    }

    func refresh() async {
        guard let client else { return }
        do { me = try await client.call("GET", "/me") } catch let e as APIError where e.status == 401 {
            signOut()
        } catch {}
    }

    /// Follows the code from the welcome letter (the invitation) on this
    /// installation: signs in, then the phone becomes the key.
    func join(server typed: String, code: String) async {
        error = nil
        guard let server = Client.serverURL(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = Client(server: server)
        do {
            let token = code.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "#").last ?? ""
            let me: Me = try await client.call("POST", "/invitation/accept", json: ["token": token])
            guard let session = me.session_token else { throw APIError(status: 0, code: "no_session", message: String(localized: "join.failed")) }
            client.token = session
            self.client = client
            self.me = me
            keep(server: server, token: session)
            stage = .welcome
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Makes the phone a passkey of the account (Face ID guards it).
    func makeKey() async {
        guard let client else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let options: CreationOptions = try await client.call("POST", "/me/passkeys/options")
            let key = try PhoneKey.make()
            let origin = WebAuthn.origin(publicURL: client.server.absoluteString)
            let rp = options.rp.id ?? WebAuthn.rpID(publicURL: client.server.absoluteString)
            let clientData = WebAuthn.clientData(type: "webauthn.create", challenge: options.challenge, origin: origin)
            let auth = WebAuthn.registrationData(rpID: rp, credentialID: key.credentialID, publicKey: key.publicKeyX963)
            let _: [String: String] = try await client.call("POST", "/me/passkeys", json: [
                "name": String(localized: "welcome.keyName"),
                "clientDataJSON": clientData.base64URL,
                "attestationObject": WebAuthn.attestationObject(authData: auth).base64URL,
            ])
            // Checked by signing in with it.
            try await signInWithKey(client: client)
            stage = .signedIn
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    /// Signs in with the phone's key.
    func signInWithKey(client: Client) async throws {
        guard let key = PhoneKey.load(), let me else { throw APIError(status: 0, code: "no_key", message: String(localized: "welcome.noKey")) }
        let options: RequestOptions = try await client.call("POST", "/session/passkey/options")
        let rp = options.rpId ?? WebAuthn.rpID(publicURL: client.server.absoluteString)
        let clientData = WebAuthn.clientData(type: "webauthn.get", challenge: options.challenge, origin: WebAuthn.origin(publicURL: client.server.absoluteString))
        let auth = WebAuthn.assertionData(rpID: rp, counter: 0)
        let signature = try key.signature(over: WebAuthn.signedBytes(authData: auth, clientData: clientData))
        let signedIn: Me = try await client.call("POST", "/session/passkey", json: [
            "id": key.credentialID.base64URL,
            "clientDataJSON": clientData.base64URL,
            "authenticatorData": auth.base64URL,
            "signature": signature.base64URL,
            "userHandle": Data(me.id.utf8).base64URL,
        ])
        if let token = signedIn.session_token {
            client.token = token
            keep(server: client.server, token: token)
        }
        self.me = signedIn
    }

    func signOut() {
        Keychain.remove("session")
        client = nil
        me = nil
        stage = .join
    }
}
