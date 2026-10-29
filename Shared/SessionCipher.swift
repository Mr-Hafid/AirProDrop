import CryptoKit
import Foundation

final class SessionCipher {
    private static let tagLength = 16

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0

    init(sendKey: SymmetricKey, receiveKey: SymmetricKey) {
        self.sendKey = sendKey
        self.receiveKey = receiveKey
    }

    func seal(_ plaintext: Data, kind: UInt8) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(plaintext, using: sendKey, nonce: try Self.nonce(for: sendCounter), authenticating: Data([kind]))
        sendCounter += 1
        return sealedBox.ciphertext + sealedBox.tag
    }

    func open(_ sealed: Data, kind: UInt8) throws -> Data {
        guard sealed.count >= Self.tagLength else { throw PeerFailure.protocolViolation }
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: try Self.nonce(for: receiveCounter),
            ciphertext: Data(sealed.prefix(sealed.count - Self.tagLength)),
            tag: Data(sealed.suffix(Self.tagLength))
        )
        let plaintext = try ChaChaPoly.open(sealedBox, using: receiveKey, authenticating: Data([kind]))
        receiveCounter += 1
        return plaintext
    }

    private static func nonce(for counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bigEndianCounter = counter.bigEndian
        let nonceBytes = Data(count: 4) + Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)
        return try ChaChaPoly.Nonce(data: nonceBytes)
    }
}
