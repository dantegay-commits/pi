import Foundation
import Security

/// Keychain wrapper for the two secrets the app holds: the HMAC shared secret
/// and the device identifier. Both are pinned to this device
/// (`ThisDeviceOnly`) so they are not carried to another iPad by an encrypted
/// backup restore, which would let two devices sign as the same courier.
enum KeychainStore {
   private static let service = "com.cindermark.pod"

   enum Key: String {
      case sharedSecret
      case deviceIdentifier
   }

   static func string(for key: Key) -> String? {
      guard let data = read(key) else { return nil }
      return String(data: data, encoding: .utf8)
   }

   @discardableResult
   static func set(_ value: String?, for key: Key) -> Bool {
      guard let value = value, !value.isEmpty else { return delete(key) }
      guard let data = value.data(using: .utf8) else { return false }
      return write(data, for: key)
   }

   /// The stable per-install device id, created the first time it is asked for.
   static func deviceIdentifier() -> String {
      if let existing = string(for: .deviceIdentifier), !existing.isEmpty { return existing }
      let generated = "ipad-" + UUID().uuidString.lowercased()
      set(generated, for: .deviceIdentifier)
      return generated
   }

   private static func query(_ key: Key) -> [String: Any] {
      [
         kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue,
      ]
   }

   private static func read(_ key: Key) -> Data? {
      var query = query(key)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
      return item as? Data
   }

   private static func write(_ data: Data, for key: Key) -> Bool {
      let query = query(key)
      let attributes: [String: Any] = [
         kSecValueData as String: data,
         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ]
      let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if status == errSecSuccess { return true }
      guard status == errSecItemNotFound else { return false }
      var insert = query
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
   }

   @discardableResult
   private static func delete(_ key: Key) -> Bool {
      let status = SecItemDelete(query(key) as CFDictionary)
      return status == errSecSuccess || status == errSecItemNotFound
   }
}
