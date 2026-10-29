import CryptoKit
import Foundation

struct DeviceIdentity {
    let signingKey: Curve25519.Signing.PrivateKey

    var publicKey: Data {
        signingKey.publicKey.rawRepresentation
    }

    static func loadOrCreate() -> DeviceIdentity {
        let store = SecureStore(account: "airprodrop.identity")
        if let stored = store.load(), let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) {
            return DeviceIdentity(signingKey: signingKey)
        }
        let signingKey = Curve25519.Signing.PrivateKey()
        store.save(signingKey.rawRepresentation)
        return DeviceIdentity(signingKey: signingKey)
    }
}
