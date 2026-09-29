import Foundation
import Security
import AcaCore
public struct KeychainStore: CredentialStore {
    private let service: String
    public init(service: String = "org.acaterminal.credentials") { self.service = service }
    private func query(_ key: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] }
    public func read(_ key: String) throws -> String? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw CoreError.invalid("Keychain could not read the credential (\(status)).") }
        return value
    }
    public func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8); var q = query(key)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CoreError.invalid("Keychain could not save the credential.") }; return
        }
        guard status == errSecSuccess else { throw CoreError.invalid("Keychain could not update the credential (\(status)).") }
    }
    public func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CoreError.invalid("Keychain could not remove the credential (\(status)).") }
    }
}
