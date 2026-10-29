import Foundation

struct TrustedDevice: Codable, Identifiable, Equatable {
    let deviceID: String
    var name: String
    let identityKey: Data
    var lastConnected: Date

    var id: String { deviceID }
}

final class TrustStore {
    private let store = SecureStore(account: "airprodrop.trustedDevices")
    private(set) var devices: [TrustedDevice]

    init() {
        devices = store.load().flatMap { try? JSONDecoder().decode([TrustedDevice].self, from: $0) } ?? []
    }

    var identityKeys: Set<Data> {
        Set(devices.map(\.identityKey))
    }

    func device(withID deviceID: String) -> TrustedDevice? {
        devices.first { $0.deviceID == deviceID }
    }

    func trust(_ peer: PeerInfo) {
        devices.removeAll { $0.deviceID == peer.deviceID || $0.identityKey == peer.identityKey }
        devices.append(TrustedDevice(deviceID: peer.deviceID, name: peer.deviceName, identityKey: peer.identityKey, lastConnected: Date()))
        persist()
    }

    func recordConnection(with peer: PeerInfo) {
        guard let index = devices.firstIndex(where: { $0.identityKey == peer.identityKey }) else { return }
        devices[index].name = peer.deviceName
        devices[index].lastConnected = Date()
        persist()
    }

    func forget(deviceID: String) {
        devices.removeAll { $0.deviceID == deviceID }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        store.save(data)
    }
}
