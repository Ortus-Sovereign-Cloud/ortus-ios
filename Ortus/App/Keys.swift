import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The phone's own passkey: a P-256 key in the Secure Enclave, used only
/// after Face ID (or the passcode). On the simulator (whose Secure Enclave
/// has no Face ID or passcode enrolled in CI), a software key in the
/// Keychain stands in.
final class PhoneKey {
    let credentialID: Data
    private let sign: (Data) throws -> Data
    let publicKeyX963: Data

    private init(credentialID: Data, publicKeyX963: Data, sign: @escaping (Data) throws -> Data) {
        self.credentialID = credentialID
        self.publicKeyX963 = publicKeyX963
        self.sign = sign
    }

    func signature(over data: Data) throws -> Data { try sign(data) }

    private static let account = "phone-key"

    private static var enclave: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return SecureEnclave.isAvailable
        #endif
    }

    /// A new key (replacing an older one).
    static func make() throws -> PhoneKey {
        let id = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        if enclave {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error) else {
                throw error!.takeRetainedValue() as Error
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access, authenticationContext: LAContext())
            Keychain.set(id + key.dataRepresentation, for: account)
            return PhoneKey(credentialID: id, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        }
        let key = P256.Signing.PrivateKey()
        Keychain.set(id + key.rawRepresentation, for: account)
        return PhoneKey(credentialID: id, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
    }

    /// The key made earlier, if any.
    static func load() -> PhoneKey? {
        guard let stored = Keychain.get(account), stored.count > 16 else { return nil }
        let id = stored.prefix(16)
        let rest = stored.dropFirst(16)
        if enclave, let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: rest, authenticationContext: LAContext()) {
            return PhoneKey(credentialID: id, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        }
        if let key = try? P256.Signing.PrivateKey(rawRepresentation: rest) {
            return PhoneKey(credentialID: id, publicKeyX963: key.publicKey.x963Representation) { try key.signature(for: $0).derRepresentation }
        }
        return nil
    }
}

/// A few values kept in the Keychain (this device only).
enum Keychain {
    static func set(_ data: Data, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func remove(_ account: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus", kSecAttrAccount as String: account] as CFDictionary)
    }
}
