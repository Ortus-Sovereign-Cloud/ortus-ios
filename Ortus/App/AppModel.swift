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
    /// The open tab (a notification's tap chooses it).
    @Published var tab = 0
    /// The installation could not be reached: screens show what was kept.
    @Published var offline = false
    /// A call answered from the system's call screen: the app opens it.
    @Published var answered: AnsweredCall?
    /// Apple's device token, kept to register again with the VoIP one.
    var apnsToken: Data?
    /// A link waiting for the person's yes (the installation it names is shown).
    @Published var confirming: InvitationLink?
    /// Messages written offline that wait to be sent.
    @Published var waiting = 0
    /// Unread notifications: the number on the bell.
    @Published var unread = 0
    private(set) var client: Client? {
        didSet { if client?.token != nil, client !== oldValue { startPush() } }
    }
    private var e2e: (client: Client, rooms: EndToEnd)?
    /// End-to-end rooms for the person signed in, made when first needed.
    func endToEnd() -> EndToEnd? {
        guard let client else { return nil }
        if let e2e, e2e.client === client { return e2e.rooms }
        let made = EndToEnd(client: client)
        e2e = (client, made)
        return made
    }
    /// The person's Matrix id, `me` of the rooms (end-to-end rooms need it).
    var chatMe: String?

    init() {
        // UI tests (and a fresh install) start clean when asked.
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            Keychain.remove("session")
            Keychain.remove("server")
            PhoneKey.forgetAll()
        }
        if let server = lastServer,
           let token = Keychain.get("session").map({ String(decoding: $0, as: UTF8.self) }) {
            client = makeClient(server, token: token)
            stage = .signedIn
            Task { await refresh() }
            startPush()
        }
    }

    /// The installation an organisation's device management set for this
    /// app (managed app configuration, key "server"), if it set one.
    var managedServer: String? {
        (UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed")?["server"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
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

    /// The bell's number, as the web's bell counts (kept when the
    /// installation cannot be reached).
    func refreshUnread() async {
        guard let client, client.token != nil, let n = try? await client.unreadNotices() else { return }
        unread = n
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
        #if DEBUG
        // Test builds say what failed, so CI shows it.
        return sayPlain(error) + " (\(String(describing: error)))"
        #else
        return sayPlain(error)
        #endif
    }

    private func sayPlain(_ error: Error) -> String {
        if let e = error as? APIError {
            if e.code == "phone_link_expired" { return String(localized: "join.phoneLinkExpired") }
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
        // A work email instead of the address: the organisation names its installation.
        var typed = typed
        if typed.contains("@") {
            busy = true
            let found = await Discovery.find(email: typed)
            busy = false
            guard let found else {
                error = String(localized: "join.notFound")
                return
            }
            typed = found.absoluteString
        }
        guard let server = server(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = makeClient(server)
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

    /// The invitation the app was last handed (a link, a scanned code).
    @Published var handed: InvitationLink?

    /// An invitation handed to the app: when no one is signed in here, its
    /// person joins at once; otherwise the phone stays with its account.
    func open(_ text: String) {
        guard let invitation = InvitationLink.parse(text) else {
            if stage == .join { error = String(localized: "join.badLink") }
            return
        }
        guard stage == .join, !busy else { return }
        handed = invitation
        // A link may come from anyone: the person sees which installation
        // it signs them into and says yes first.
        confirming = invitation
    }

    /// Says yes to the link waiting for it.
    func confirmLink() {
        guard let invitation = confirming else { return }
        confirming = nil
        switch invitation.kind {
        case .invite: Task { await join(server: invitation.server, code: invitation.code) }
        case .phone: Task { await signInWithPhoneLink(server: invitation.server, code: invitation.code) }
        }
    }

    /// "Sign in on your phone" from the web: the code signs this phone in as
    /// the person; a phone that is not yet their key becomes it next.
    func signInWithPhoneLink(server typed: String, code: String) async {
        error = nil
        guard let server = server(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = makeClient(server)
        do {
            let me: Me = try await client.call("POST", "/session/phone-link", json: ["token": code])
            guard let session = me.session_token else { throw APIError(status: 0, code: "no_session", message: "") }
            client.token = session
            self.client = client
            self.me = me
            keep(server: server, token: session)
            stage = PhoneKey.load(for: server) == nil ? .welcome : .signedIn
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

    /// The ticket between the password and the one-time code.
    @Published var ticket: String?
    private var pending: Client?

    /// Signing in with a password: then the code from the authenticator
    /// app (a password alone never signs in to Ortus).
    func signInWithPassword(server typed: String, email: String, password: String) async {
        error = nil
        guard let server = server(from: typed) else {
            error = String(localized: "join.badServer")
            return
        }
        busy = true
        defer { busy = false }
        let client = makeClient(server)
        do {
            struct Next: Decodable { let ticket: String? }
            let next: Next = try await client.call("POST", "/session/password", json: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
            guard let t = next.ticket else { throw APIError(status: 0, code: "no_ticket", message: "") }
            pending = client
            ticket = t
        } catch let e as APIError where e.status == 401 {
            error = String(localized: "join.wrong")
        } catch {
            self.error = say(error)
        }
    }

    func signInWithCode(_ code: String) async {
        guard let client = pending, let ticket else { return }
        error = nil
        busy = true
        defer { busy = false }
        do {
            let me: Me = try await client.call("POST", "/session/code", json: ["ticket": ticket, "code": code.filter(\.isNumber)])
            guard let session = me.session_token else { throw APIError(status: 0, code: "no_session", message: "") }
            client.token = session
            self.client = client
            self.me = me
            keep(server: client.server, token: session)
            self.ticket = nil
            pending = nil
            // A phone that is not yet their key becomes it next.
            stage = PhoneKey.load(for: client.server) == nil ? .welcome : .signedIn
        } catch {
            if (error as? APIError)?.code == "ticket_expired" { self.ticket = nil }
            self.error = say(error)
        }
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
        let client = makeClient(server)
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
        if let client {
            PushStore.remove(server: client.server)
            forgetKept(client.server)
        }
        Keychain.remove("session")
        client = nil
        me = nil
        unread = 0
        stage = .join
    }

    /// Ends the session on the server too. The key stays: the phone is
    /// still the person's key (an administrator turns off a lost phone's).
    func signOut() async {
        await stopPush()
        // End-to-end rooms: the server drops this device, the phone its keys.
        var me = chatMe
        if me == nil, let client { me = try? await client.rooms().me }
        await endToEnd()?.forget(me: me)
        chatMe = nil
        if let client, let token = client.token { await end(session: token, on: client.server) }
        ended()
    }
}
