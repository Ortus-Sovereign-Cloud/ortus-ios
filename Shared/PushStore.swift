import Foundation
import OrtusKit
import Security

/// The fetch token of each installation, where the notification extension
/// can read it: a keychain group the app and the extension share (the
/// session and the phone's key are not in it), readable after the phone's
/// first unlock, since pushes mostly arrive while it is locked.
enum PushStore {
    /// The shared group in store builds; test builds (signed ad hoc, no
    /// groups) keep it in the app's own.
    private static var group: String? {
        #if DEBUG
        return nil
        #else
        return "XD7JHZ5DB3.cc.ortus.shared"
        #endif
    }

    private static func query(_ server: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ortus-push", kSecAttrAccount as String: server]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func save(_ registration: PushRegistration, server: URL) {
        let q = query(server.absoluteString)
        SecItemDelete(q as CFDictionary)
        guard let data = try? JSONEncoder().encode(registration) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(server: URL) -> PushRegistration? {
        var q = query(server.absoluteString)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(PushRegistration.self, from: data)
    }

    static func remove(server: URL) {
        SecItemDelete(query(server.absoluteString) as CFDictionary)
    }
}
