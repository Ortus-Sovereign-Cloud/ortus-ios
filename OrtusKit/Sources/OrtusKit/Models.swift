import Foundation

/// The signed-in person (GET /me), and the session token when signing in.
public struct Me: Decodable, Equatable {
    public let id: String
    public let email: String
    public let name: String
    public let role: String
    public let session_token: String?
}

/// Options for making a passkey (POST /me/passkeys/options).
public struct CreationOptions: Decodable {
    public struct RP: Decodable { public let id: String?; public let name: String? }
    public struct User: Decodable { public let id: String; public let name: String }
    public let challenge: String
    public let rp: RP
    public let user: User
}

/// Options for signing in with a passkey (POST /session/passkey/options).
public struct RequestOptions: Decodable {
    public let challenge: String
    public let rpId: String?
}
