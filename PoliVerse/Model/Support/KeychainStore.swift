import Foundation
import Security

/// Keychain storage for the OAuth token pair.
///
/// Items are generic passwords under one service, accessible after first unlock and
/// marked this-device-only, so they are never written to iCloud and never restored
/// onto another device. These are long-lived credentials to a student's academic
/// record, which is why they are not kept in a file in the app container.
nonisolated enum KeychainStore {
    /// A Keychain call that did not succeed, carrying its `OSStatus`.
    enum Failure: Error { case status(OSStatus) }

    /// The `kSecAttrService` every item is filed under.
    private static let service = "segrini.samuele.PoliVerse.tokens"

    /// Stores bytes for an account, updating an existing item or adding a new one.
    ///
    /// - Parameters:
    ///   - data: The bytes to store.
    ///   - account: The `kSecAttrAccount` to file them under.
    /// - Throws: ``Failure/status(_:)`` when the update or the insert fails.
    static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let insert = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.status(addStatus) }
        default:
            throw Failure.status(status)
        }
    }

    /// Reads the bytes stored for an account.
    ///
    /// - Parameter account: The `kSecAttrAccount` to look under.
    /// - Returns: The stored bytes, or `nil` when there is no item or the read fails.
    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Removes the item stored for an account. A missing item is not an error.
    ///
    /// - Parameter account: The `kSecAttrAccount` to remove.
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
