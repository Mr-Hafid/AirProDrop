import CryptoKit
import Foundation
import Security

enum PeerFailure: String, Error, Codable {
    case network
    case timeout
    case untrusted
    case passkeyMismatch
    case notAcceptingPairing
    case protocolViolation
}

struct PeerInfo: Equatable {
    let deviceID: String
    let deviceName: String
    let identityKey: Data
    let didPair: Bool
}

struct HandshakeIntroduction: Codable, Equatable {
    let deviceID: String
    let deviceName: String
    let identityKey: Data
    let ephemeralKey: Data
}

enum HandshakeMessage: Codable {
    case resumeHello(HandshakeIntroduction, nonce: Data)
    case resumeAccept(HandshakeIntroduction, nonce: Data, signature: Data)
    case resumeConfirm(signature: Data)
    case pairHello(HandshakeIntroduction)
    case pairAccept(HandshakeIntroduction)
    case commitment(Data)
    case reveal(Data)
    case pairConfirm(signature: Data)
    case codeRequest(deviceName: String)
    case codeDisplayed
    case rejected(PeerFailure)
}

enum HandshakeRole {
    case resume(expectedIdentityKey: Data)
    case pair(passkey: Int)
    case requestCode
    case respond(trustedIdentityKeys: Set<Data>, passkey: Int?, acceptsCodeRequests: Bool)
}

enum HandshakeStep {
    case send([HandshakeMessage])
    case established(SessionCipher, PeerInfo, send: [HandshakeMessage])
    case pairingCodeDisplayed(requesterName: String, send: [HandshakeMessage])
}

final class SecureHandshake {
    static let passkeyBitCount = 20

    private enum Stage {
        case idle
        case awaitingResumeAccept
        case awaitingResumeConfirm
        case awaitingPairAccept
        case awaitingCommitment
        case awaitingReveal
        case awaitingPairConfirm
        case awaitingCodeDisplayed
        case finished
    }

    private static let resumeLabel = Data("AirProDrop/resume/v1".utf8)
    private static let pairLabel = Data("AirProDrop/pair/v1".utf8)
    private static let initiatorTag = Data("initiator".utf8)
    private static let responderTag = Data("responder".utf8)

    private let role: HandshakeRole
    private let identity: DeviceIdentity
    private let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
    private let local: HandshakeIntroduction
    private var remote: HandshakeIntroduction?
    private var localNonce = Data()
    private var remoteNonce = Data()
    private var passkey = 0
    private var round = 0
    private var localRoundNonce = Data()
    private var remoteCommitment = Data()
    private var stage = Stage.idle

    init(role: HandshakeRole, identity: DeviceIdentity, deviceID: String, deviceName: String) {
        self.role = role
        self.identity = identity
        local = HandshakeIntroduction(
            deviceID: deviceID,
            deviceName: deviceName,
            identityKey: identity.publicKey,
            ephemeralKey: ephemeralKey.publicKey.rawRepresentation
        )
    }

    var isInitiator: Bool {
        if case .respond = role { return false }
        return true
    }

    func start() -> [HandshakeMessage] {
        switch role {
        case .resume:
            localNonce = Self.randomBytes(32)
            stage = .awaitingResumeAccept
            return [.resumeHello(local, nonce: localNonce)]
        case .pair(let passkey):
            self.passkey = passkey
            stage = .awaitingPairAccept
            return [.pairHello(local)]
        case .requestCode:
            stage = .awaitingCodeDisplayed
            return [.codeRequest(deviceName: local.deviceName)]
        case .respond:
            stage = .idle
            return []
        }
    }

    func receive(_ message: HandshakeMessage) throws -> HandshakeStep {
        if case .rejected(let reason) = message {
            throw reason
        }
        switch (stage, message) {
        case (.idle, .resumeHello(let introduction, let nonce)):
            guard case .respond(let trustedIdentityKeys, _, _) = role, trustedIdentityKeys.contains(introduction.identityKey) else {
                throw PeerFailure.untrusted
            }
            remote = introduction
            remoteNonce = nonce
            localNonce = Self.randomBytes(32)
            let signature = try identity.signingKey.signature(for: try resumeTranscript())
            stage = .awaitingResumeConfirm
            return .send([.resumeAccept(local, nonce: localNonce, signature: signature)])

        case (.awaitingResumeAccept, .resumeAccept(let introduction, let nonce, let signature)):
            guard case .resume(let expectedIdentityKey) = role, introduction.identityKey == expectedIdentityKey else {
                throw PeerFailure.untrusted
            }
            remote = introduction
            remoteNonce = nonce
            let transcript = try resumeTranscript()
            try verify(signature, over: transcript, signedBy: introduction.identityKey)
            let confirmation = try identity.signingKey.signature(for: transcript + Self.initiatorTag)
            return try establish(transcript: transcript, didPair: false, send: [.resumeConfirm(signature: confirmation)])

        case (.awaitingResumeConfirm, .resumeConfirm(let signature)):
            let transcript = try resumeTranscript()
            try verify(signature, over: transcript + Self.initiatorTag, signedBy: try remoteIntroduction().identityKey)
            return try establish(transcript: transcript, didPair: false, send: [])

        case (.idle, .pairHello(let introduction)):
            guard case .respond(_, let passkey?, _) = role else { throw PeerFailure.notAcceptingPairing }
            self.passkey = passkey
            remote = introduction
            stage = .awaitingCommitment
            return .send([.pairAccept(local)])

        case (.idle, .codeRequest(let deviceName)):
            guard case .respond(_, _, true) = role else { throw PeerFailure.notAcceptingPairing }
            stage = .finished
            return .pairingCodeDisplayed(requesterName: deviceName, send: [.codeDisplayed])

        case (.awaitingCodeDisplayed, .codeDisplayed):
            stage = .finished
            return .pairingCodeDisplayed(requesterName: local.deviceName, send: [])

        case (.awaitingPairAccept, .pairAccept(let introduction)):
            remote = introduction
            return .send([try beginInitiatorRound()])

        case (.awaitingCommitment, .commitment(let receivedCommitment)):
            remoteCommitment = receivedCommitment
            stage = .awaitingReveal
            if isInitiator {
                return .send([.reveal(localRoundNonce)])
            }
            localRoundNonce = Self.randomBytes(16)
            return .send([.commitment(try commitment(nonce: localRoundNonce, fromLocal: true))])

        case (.awaitingReveal, .reveal(let nonce)):
            guard try isValid(remoteCommitment, nonce: nonce) else { throw PeerFailure.passkeyMismatch }
            round += 1
            if isInitiator {
                if round < Self.passkeyBitCount {
                    return .send([try beginInitiatorRound()])
                }
                stage = .awaitingPairConfirm
                let confirmation = try identity.signingKey.signature(for: try pairTranscript() + Self.initiatorTag)
                return .send([.pairConfirm(signature: confirmation)])
            }
            stage = round < Self.passkeyBitCount ? .awaitingCommitment : .awaitingPairConfirm
            return .send([.reveal(localRoundNonce)])

        case (.awaitingPairConfirm, .pairConfirm(let signature)):
            let transcript = try pairTranscript()
            let remoteIdentityKey = try remoteIntroduction().identityKey
            if isInitiator {
                try verify(signature, over: transcript + Self.responderTag, signedBy: remoteIdentityKey)
                return try establish(transcript: transcript, didPair: true, send: [])
            }
            try verify(signature, over: transcript + Self.initiatorTag, signedBy: remoteIdentityKey)
            let confirmation = try identity.signingKey.signature(for: transcript + Self.responderTag)
            return try establish(transcript: transcript, didPair: true, send: [.pairConfirm(signature: confirmation)])

        default:
            throw PeerFailure.protocolViolation
        }
    }

    private func beginInitiatorRound() throws -> HandshakeMessage {
        localRoundNonce = Self.randomBytes(16)
        stage = .awaitingCommitment
        return .commitment(try commitment(nonce: localRoundNonce, fromLocal: true))
    }

    private func commitment(nonce: Data, fromLocal: Bool) throws -> Data {
        let remote = try remoteIntroduction()
        let sender = fromLocal ? local : remote
        let receiver = fromLocal ? remote : local
        let bit = UInt8((passkey >> round) & 1)
        let input = sender.identityKey + sender.ephemeralKey + receiver.identityKey + receiver.ephemeralKey + Data([bit])
        return Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: nonce)))
    }

    private func isValid(_ commitment: Data, nonce: Data) throws -> Bool {
        let remote = try remoteIntroduction()
        let bit = UInt8((passkey >> round) & 1)
        let input = remote.identityKey + remote.ephemeralKey + local.identityKey + local.ephemeralKey + Data([bit])
        return HMAC<SHA256>.isValidAuthenticationCode(commitment, authenticating: input, using: SymmetricKey(data: nonce))
    }

    private func resumeTranscript() throws -> Data {
        let remote = try remoteIntroduction()
        let (initiator, initiatorNonce, responder, responderNonce) = isInitiator
            ? (local, localNonce, remote, remoteNonce)
            : (remote, remoteNonce, local, localNonce)
        return Self.resumeLabel
            + initiator.identityKey + initiator.ephemeralKey + initiatorNonce
            + responder.identityKey + responder.ephemeralKey + responderNonce
    }

    private func pairTranscript() throws -> Data {
        let remote = try remoteIntroduction()
        let (initiator, responder) = isInitiator ? (local, remote) : (remote, local)
        return Self.pairLabel
            + initiator.identityKey + initiator.ephemeralKey
            + responder.identityKey + responder.ephemeralKey
    }

    private func establish(transcript: Data, didPair: Bool, send messages: [HandshakeMessage]) throws -> HandshakeStep {
        let remote = try remoteIntroduction()
        let remoteEphemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remote.ephemeralKey)
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: remoteEphemeralKey)
        let salt = Data(SHA256.hash(data: transcript))
        let initiatorToResponder = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("i2r".utf8), outputByteCount: 32)
        let responderToInitiator = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("r2i".utf8), outputByteCount: 32)
        let cipher = isInitiator
            ? SessionCipher(sendKey: initiatorToResponder, receiveKey: responderToInitiator)
            : SessionCipher(sendKey: responderToInitiator, receiveKey: initiatorToResponder)
        stage = .finished
        let peer = PeerInfo(deviceID: remote.deviceID, deviceName: remote.deviceName, identityKey: remote.identityKey, didPair: didPair)
        return .established(cipher, peer, send: messages)
    }

    private func verify(_ signature: Data, over data: Data, signedBy identityKey: Data) throws {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identityKey)
        guard publicKey.isValidSignature(signature, for: data) else { throw PeerFailure.untrusted }
    }

    private func remoteIntroduction() throws -> HandshakeIntroduction {
        guard let remote else { throw PeerFailure.protocolViolation }
        return remote
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
