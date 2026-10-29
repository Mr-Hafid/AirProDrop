import Foundation
import Security

struct SecureStore {
    let account: String
    private let service = "com.mrhafid.airprodrop"

    #if os(macOS)
    func load() -> Data? {
        UserDefaults.standard.data(forKey: account)
    }

    func save(_ data: Data) {
        UserDefaults.standard.set(data, forKey: account)
    }

    func delete() {
        UserDefaults.standard.removeObject(forKey: account)
    }
    #else
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ data: Data) {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
    #endif
}
