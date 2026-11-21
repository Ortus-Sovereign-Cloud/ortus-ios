import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The phone's own passkey: a P-256 key in the Secure Enclave, used only
/// after Face ID (or the passcode), one per installation. On the simulator
/// (whose Secure Enclave has no Face ID or passcode enrolled in CI) a
/// software key stands in; on a phone there is no software key at all.
final class PhoneKey {
    let credentialID: Data
    private let sign: (Data) throws -> Data
    private let stored: Data
    let publicKeyX963: Data

    private init(credentialID: Data, stored: Data, publicKeyX963: Data, sign: @escaping (Data) throws -> Data) {
        self.credentialID = credentialID
        self.stored = stored
        self.publicKeyX963 = publicKeyX963
        self.sign = sign
    }

    func signature(over data: Data) throws -> Data { try sign(data) }

    struct NoSecureEnclave: LocalizedError {
        var errorDescription: String? { String(localized: "key.noLock") }
    }

    private static func account(_ server: URL) -> String { "phone-key:" + WebAuthn.origin(publicURL: server.absoluteString) }

    /// A new key, not yet the phone's key for the installation (see `keep`).
    static func make() throws -> PhoneKey {
        let id = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        #if targetEnvironment(simulator)
        let key = P256.Signing.PrivateKey()
        return PhoneKey(credentialID: id, stored: id + key.rawRepresentation, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        #else
        guard SecureEnclave.isAvailable else { throw NoSecureEnclave() }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage, .userPresence], &error) else {
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: LAContext())
        return PhoneKey(credentialID: id, stored: id + key.dataRepresentation, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        #endif
    }

    /// The key (registered by the installation) becomes the phone's key
    /// for it, replacing an older one only now.
    func keep(for server: URL) throws {
        try Keychain.set(stored, for: Self.account(server))
    }

    /// The phone's key for the installation, if any.
    static func load(for server: URL) -> PhoneKey? {
        guard let stored = Keychain.get(account(server)), stored.count > 16 else { return nil }
        let id = stored.prefix(16)
        let rest = stored.dropFirst(16)
        #if targetEnvironment(simulator)
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: rest) else { return nil }
        return PhoneKey(credentialID: id, stored: stored, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        #else
        guard SecureEnclave.isAvailable, let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: rest, authenticationContext: LAContext()) else { return nil }
        return PhoneKey(credentialID: id, stored: stored, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        #endif
    }

    static func forget(for server: URL) { Keychain.remove(account(server)) }

    /// Every installation's key (a test run starts clean).
    static func forgetAll() { Keychain.removeAll(prefix: "phone-key") }
}

/// A few values kept in the Keychain (this device only).
enum Keychain {
    struct NotKept: Error { let status: OSStatus }

    /// Keeps the value (replacing an older one); throws when the Keychain refuses.
    @discardableResult
    static func set(_ data: Data, for account: String) throws -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NotKept(status: status) }
        return true
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func removeAll(prefix: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let items = out as? [[String: Any]] else { return }
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) { remove(account) }
        }
    }

    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account] as CFDictionary)
    }
}
