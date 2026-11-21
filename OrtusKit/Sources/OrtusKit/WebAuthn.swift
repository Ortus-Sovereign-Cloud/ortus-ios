// The phone as a passkey: the app holds a P-256 key (in the Secure Enclave
// on a device) and speaks WebAuthn to the installation the way a browser's
// authenticator would, through the same API the web client uses
// (/me/passkeys and /session/passkey). Nothing here signs: the app passes
// the signer in, so the encoding is tested anywhere.
import Foundation

public enum WebAuthn {
    /// The authenticator model, all zeros as for "none" attestation.
    public static let aaguid = Data(repeating: 0, count: 16)

    /// clientDataJSON as a browser would send it.
    public static func clientData(type: String, challenge: String, origin: String) -> Data {
        // Keys in the order browsers use; values escaped as JSON strings.
        func json(_ s: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
            let text = String(decoding: data, as: UTF8.self)
            return String(text.dropFirst().dropLast())
        }
        return Data("{\"type\":\(json(type)),\"challenge\":\(json(challenge)),\"origin\":\(json(origin)),\"crossOrigin\":false}".utf8)
    }

    /// The relying party id of an installation: its host.
    public static func rpID(publicURL: String) -> String {
        (URL(string: publicURL)?.host ?? publicURL).lowercased()
    }

    /// The web origin of an address, as a browser writes it (and as the
    /// installation compares it with its public_url): lower-case scheme and
    /// host, the port only when not the scheme's own, no path.
    public static func origin(publicURL: String) -> String {
        guard let url = URL(string: publicURL.trimmingCharacters(in: .whitespaces)), let host = url.host else {
            var text = publicURL
            while text.hasSuffix("/") { text.removeLast() }
            return text
        }
        let scheme = (url.scheme ?? "https").lowercased()
        var origin = "\(scheme)://\(host.lowercased())"
        if let port = url.port, !(scheme == "https" && port == 443), !(scheme == "http" && port == 80) { origin += ":\(port)" }
        return origin
    }

    /// The relying party id the installation asks for, when it is the host
    /// the phone talks to or a parent domain of it; otherwise the key would
    /// sign for another site, and it is refused.
    public static func checkedRPID(_ asked: String?, publicURL: String) throws -> String {
        let host = rpID(publicURL: publicURL)
        guard let rp = asked?.lowercased() else { return host }
        if rp == host || host.hasSuffix("." + rp) { return rp }
        throw APIError(status: 0, code: "bad_rp", message: "The server asked for a key of another site.")
    }

    /// The COSE form of a P-256 public key given as its X9.63 form
    /// (0x04 ‖ x ‖ y).
    public static func coseKey(x963: Data) -> Data {
        let bytes = [UInt8](x963)
        precondition(bytes.count == 65 && bytes[0] == 4, "an uncompressed P-256 point")
        return CBOR.map([
            (.unsigned(1), .unsigned(2)),        // kty: EC2
            (.unsigned(3), .negative(-7)),       // alg: ES256
            (.negative(-1), .unsigned(1)),       // crv: P-256
            (.negative(-2), .bytes(Data(bytes[1..<33]))),
            (.negative(-3), .bytes(Data(bytes[33..<65]))),
        ]).encoded
    }

    static let userPresent: UInt8 = 0x01
    static let userVerified: UInt8 = 0x04
    static let attested: UInt8 = 0x40

    /// authenticatorData for a new credential.
    public static func registrationData(rpID: String, credentialID: Data, publicKey x963: Data) -> Data {
        var out = SHA256.hash(Data(rpID.utf8))
        out.append(userPresent | userVerified | attested)
        out.append(contentsOf: [0, 0, 0, 0])
        out.append(aaguid)
        out.append(contentsOf: [UInt8(credentialID.count >> 8), UInt8(credentialID.count & 0xff)])
        out.append(credentialID)
        out.append(coseKey(x963: x963))
        return out
    }

    /// The attestation object ("none") for a new credential.
    public static func attestationObject(authData: Data) -> Data {
        CBOR.map([
            (.text("fmt"), .text("none")),
            (.text("attStmt"), .map([])),
            (.text("authData"), .bytes(authData)),
        ]).encoded
    }

    /// authenticatorData for a sign-in (no credential data).
    public static func assertionData(rpID: String, counter: UInt32 = 0) -> Data {
        var out = SHA256.hash(Data(rpID.utf8))
        out.append(userPresent | userVerified)
        out.append(contentsOf: [UInt8(counter >> 24), UInt8((counter >> 16) & 0xff), UInt8((counter >> 8) & 0xff), UInt8(counter & 0xff)])
        return out
    }

    /// What the key signs for a sign-in: authenticatorData ‖ SHA-256(clientData).
    public static func signedBytes(authData: Data, clientData: Data) -> Data {
        authData + SHA256.hash(clientData)
    }
}
