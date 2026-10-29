import Foundation
import Network

enum PeerEvent {
    case ready(PeerInfo)
    case pairingCodeDisplayed(requesterName: String)
    case closed(PeerFailure?)
    case message(ControlMessage)
    case bytesReceived(transferID: UUID, totalBytes: Int64)
    case fileReceived(transferID: UUID, temporaryURL: URL)
}

final class PeerConnection {
    private enum FrameKind: UInt8 {
        case control = 1
        case fileChunk = 2
        case fileEnd = 3
        case handshake = 4
    }

    private struct IncomingFile {
        let handle: FileHandle
        let url: URL
        var receivedBytes: Int64
    }

    var onEvent: ((PeerEvent) -> Void)?

    private let connection: NWConnection
    private let handshake: SecureHandshake
    private let queue = DispatchQueue(label: "com.mrhafid.airprodrop.connection")
    private var cipher: SessionCipher?
    private var incomingFiles: [UUID: IncomingFile] = [:]
    private var hasTerminated = false

    init(connection: NWConnection, handshake: SecureHandshake) {
        self.connection = connection
        self.handshake = handshake
    }

    convenience init(endpoint: NWEndpoint, handshake: SecureHandshake) {
        self.init(connection: NWConnection(to: endpoint, using: .airProTransport), handshake: handshake)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.handshake.start().forEach(self.sendHandshake)
                self.receiveNextFrame()
            case .failed, .waiting:
                self.terminate(with: .network)
            case .cancelled:
                self.terminate(with: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + AirProService.handshakeTimeout) { [weak self] in
            guard let self, self.cipher == nil, !self.hasTerminated else { return }
            self.terminate(with: .timeout)
        }
    }

    func cancel() {
        connection.cancel()
    }

    func send(_ message: ControlMessage, completion: (() -> Void)? = nil) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        sendFrame(kind: .control, payload: payload) { _ in
            guard let completion else { return }
            DispatchQueue.main.async(execute: completion)
        }
    }

    func sendFile(at url: URL, transferID: UUID, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.sendNextChunk(from: handle, transferID: transferID, completion: completion)
        }
    }

    private func sendNextChunk(from handle: FileHandle, transferID: UUID, completion: @escaping (Bool) -> Void) {
        let chunk = (try? handle.read(upToCount: AirProService.fileChunkLength)) ?? Data()
        if chunk.isEmpty {
            try? handle.close()
            sendFrame(kind: .fileEnd, payload: transferID.dataRepresentation) { succeeded in
                DispatchQueue.main.async { completion(succeeded) }
            }
            return
        }
        sendFrame(kind: .fileChunk, payload: transferID.dataRepresentation + chunk) { [weak self] succeeded in
            guard let self, succeeded, !self.hasTerminated else {
                try? handle.close()
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.sendNextChunk(from: handle, transferID: transferID, completion: completion)
        }
    }

    private func sendHandshake(_ message: HandshakeMessage) {
        sendHandshake(message, completion: nil)
    }

    private func sendHandshake(_ message: HandshakeMessage, completion: (() -> Void)?) {
        guard let payload = try? JSONEncoder().encode(message) else { return }
        sendFrame(kind: .handshake, payload: payload) { _ in completion?() }
    }

    private func sendFrame(kind: FrameKind, payload: Data, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard !self.hasTerminated else {
                completion(false)
                return
            }
            let body: Data
            if kind == .handshake {
                body = payload
            } else {
                guard let cipher = self.cipher, let sealed = try? cipher.seal(payload, kind: kind.rawValue) else {
                    completion(false)
                    return
                }
                body = sealed
            }
            var frame = Data([kind.rawValue])
            var bigEndianLength = UInt32(body.count).bigEndian
            frame.append(Data(bytes: &bigEndianLength, count: MemoryLayout<UInt32>.size))
            frame.append(body)
            self.connection.send(content: frame, completion: .contentProcessed { error in
                completion(error == nil)
            })
        }
    }

    private func receiveNextFrame() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let header, header.count == 5 else {
                self.terminate(with: .network)
                return
            }
            let headerBytes = Array(header)
            let payloadLength = headerBytes[1...4].reduce(0) { $0 << 8 | Int($1) }
            guard let kind = FrameKind(rawValue: headerBytes[0]), payloadLength <= AirProService.maximumFrameLength else {
                self.terminate(with: .protocolViolation)
                return
            }
            guard payloadLength > 0 else {
                self.handleFrame(kind: kind, payload: Data())
                isComplete ? self.connection.cancel() : self.receiveNextFrame()
                return
            }
            self.connection.receive(minimumIncompleteLength: payloadLength, maximumLength: payloadLength) { payload, _, isComplete, error in
                guard error == nil, let payload, payload.count == payloadLength else {
                    self.terminate(with: .network)
                    return
                }
                self.handleFrame(kind: kind, payload: payload)
                guard !self.hasTerminated else { return }
                isComplete ? self.connection.cancel() : self.receiveNextFrame()
            }
        }
    }

    private func handleFrame(kind: FrameKind, payload: Data) {
        if kind == .handshake {
            handleHandshake(payload)
            return
        }
        guard let cipher, let plaintext = try? cipher.open(payload, kind: kind.rawValue) else {
            terminate(with: .protocolViolation)
            return
        }
        switch kind {
        case .control:
            guard let message = try? JSONDecoder().decode(ControlMessage.self, from: plaintext) else { return }
            emit(.message(message))
        case .fileChunk:
            guard let transferID = UUID(dataRepresentation: plaintext.prefix(16)) else { return }
            appendChunk(plaintext.dropFirst(16), to: transferID)
        case .fileEnd:
            guard let transferID = UUID(dataRepresentation: plaintext.prefix(16)) else { return }
            finishFile(transferID)
        case .handshake:
            break
        }
    }

    private func handleHandshake(_ payload: Data) {
        guard cipher == nil, let message = try? JSONDecoder().decode(HandshakeMessage.self, from: payload) else {
            terminate(with: .protocolViolation)
            return
        }
        do {
            switch try handshake.receive(message) {
            case .send(let messages):
                messages.forEach(sendHandshake)
            case .established(let sessionCipher, let peer, let messages):
                messages.forEach(sendHandshake)
                cipher = sessionCipher
                emit(.ready(peer))
            case .pairingCodeDisplayed(let requesterName, let messages):
                emit(.pairingCodeDisplayed(requesterName: requesterName))
                closeAfterSending(messages)
            }
        } catch {
            let failure = error as? PeerFailure ?? .protocolViolation
            if case .rejected = message {
                terminate(with: failure)
                return
            }
            sendHandshake(.rejected(failure)) { [weak self] in
                self?.queue.async { self?.terminate(with: failure) }
            }
        }
    }

    private func closeAfterSending(_ messages: [HandshakeMessage]) {
        guard let finalMessage = messages.last else {
            terminate(with: nil)
            return
        }
        messages.dropLast().forEach(sendHandshake)
        sendHandshake(finalMessage) { [weak self] in
            self?.queue.async { self?.terminate(with: nil) }
        }
    }

    private func appendChunk(_ chunk: Data, to transferID: UUID) {
        if incomingFiles[transferID] == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("airprodrop-\(transferID.uuidString)")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            incomingFiles[transferID] = IncomingFile(handle: handle, url: url, receivedBytes: 0)
        }
        guard var incomingFile = incomingFiles[transferID] else { return }
        incomingFile.handle.write(chunk)
        incomingFile.receivedBytes += Int64(chunk.count)
        incomingFiles[transferID] = incomingFile
        emit(.bytesReceived(transferID: transferID, totalBytes: incomingFile.receivedBytes))
    }

    private func finishFile(_ transferID: UUID) {
        if incomingFiles[transferID] == nil {
            appendChunk(Data(), to: transferID)
        }
        guard let incomingFile = incomingFiles.removeValue(forKey: transferID) else { return }
        try? incomingFile.handle.close()
        emit(.fileReceived(transferID: transferID, temporaryURL: incomingFile.url))
    }

    private func terminate(with failure: PeerFailure?) {
        guard !hasTerminated else { return }
        hasTerminated = true
        for incomingFile in incomingFiles.values {
            try? incomingFile.handle.close()
            try? FileManager.default.removeItem(at: incomingFile.url)
        }
        incomingFiles.removeAll()
        connection.cancel()
        emit(.closed(failure))
    }

    private func emit(_ event: PeerEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}

private extension UUID {
    var dataRepresentation: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init?(dataRepresentation data: Data) {
        guard data.count == 16 else { return nil }
        self = UUID(uuid: data.withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
    }
}
