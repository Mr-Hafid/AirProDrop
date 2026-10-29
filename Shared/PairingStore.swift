import Foundation
import Security

struct PairedPeer: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var sharedSecret: Data
}

final class PairingStore {
    private let account = "airpro.pairedPeer"
    private let service = "com.mobileprintsoft.airpro"
    private var sessionPeer: PairedPeer?
    private var hasLoadedPeer = false

    var pairedPeer: PairedPeer? {
        get {
            if !hasLoadedPeer {
                hasLoadedPeer = true
                sessionPeer = loadData().flatMap { try? JSONDecoder().decode(PairedPeer.self, from: $0) }
            }
            return sessionPeer
        }
        set {
            hasLoadedPeer = true
            sessionPeer = newValue
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                saveData(data)
            } else {
                deleteData()
            }
        }
    }

    static func makeSharedSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    #if os(macOS)
    private func loadData() -> Data? {
        UserDefaults.standard.data(forKey: account)
    }

    private func saveData(_ data: Data) {
        UserDefaults.standard.set(data, forKey: account)
    }

    private func deleteData() {
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

    private func loadData() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func saveData(_ data: Data) {
        deleteData()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteData() {
        SecItemDelete(baseQuery as CFDictionary)
    }
    #endif
}
