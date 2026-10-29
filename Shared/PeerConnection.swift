import Foundation
import Network

enum PeerEvent {
    case ready
    case closed(NWError?)
    case message(ControlMessage)
    case bytesReceived(transferID: UUID, totalBytes: Int64)
    case fileReceived(transferID: UUID, temporaryURL: URL)
}

final class PeerConnection {
    private enum FrameKind: UInt8 {
        case control = 1
        case fileChunk = 2
        case fileEnd = 3
    }

    private struct IncomingFile {
        let handle: FileHandle
        let url: URL
        var receivedBytes: Int64
    }

    var onEvent: ((PeerEvent) -> Void)?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.mobileprintsoft.airpro.connection")
    private var incomingFiles: [UUID: IncomingFile] = [:]
    private var hasTerminated = false
    private(set) var isReady = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    convenience init(endpoint: NWEndpoint, sharedSecret: Data) {
        self.init(connection: NWConnection(to: endpoint, using: .airPro(sharedSecret: sharedSecret)))
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                self.emit(.ready)
                self.receiveNextFrame()
            case .failed(let error), .waiting(let error):
                self.terminate(with: error)
            case .cancelled:
                self.terminate(with: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + AirProService.handshakeTimeout) { [weak self] in
            guard let self, !self.isReady, !self.hasTerminated else { return }
            self.terminate(with: nil)
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
            sendFrame(kind: .fileEnd, payload: transferID.dataRepresentation) { error in
                DispatchQueue.main.async { completion(error == nil) }
            }
            return
        }
        sendFrame(kind: .fileChunk, payload: transferID.dataRepresentation + chunk) { [weak self] error in
            guard let self, error == nil, !self.hasTerminated else {
                try? handle.close()
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.sendNextChunk(from: handle, transferID: transferID, completion: completion)
        }
    }

    private func sendFrame(kind: FrameKind, payload: Data, completion: @escaping (NWError?) -> Void) {
        var frame = Data([kind.rawValue])
        var bigEndianLength = UInt32(payload.count).bigEndian
        frame.append(Data(bytes: &bigEndianLength, count: MemoryLayout<UInt32>.size))
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed(completion))
    }

    private func receiveNextFrame() {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            guard error == nil, let header, header.count == 5 else {
                self.terminate(with: error)
                return
            }
            let headerBytes = Array(header)
            let payloadLength = headerBytes[1...4].reduce(0) { $0 << 8 | Int($1) }
            guard let kind = FrameKind(rawValue: headerBytes[0]), payloadLength <= AirProService.maximumFrameLength else {
                self.connection.cancel()
                return
            }
            guard payloadLength > 0 else {
                self.handleFrame(kind: kind, payload: Data())
                isComplete ? self.connection.cancel() : self.receiveNextFrame()
                return
            }
            self.connection.receive(minimumIncompleteLength: payloadLength, maximumLength: payloadLength) { payload, _, isComplete, error in
                guard error == nil, let payload, payload.count == payloadLength else {
                    self.terminate(with: error)
                    return
                }
                self.handleFrame(kind: kind, payload: payload)
                isComplete ? self.connection.cancel() : self.receiveNextFrame()
            }
        }
    }

    private func handleFrame(kind: FrameKind, payload: Data) {
        switch kind {
        case .control:
            guard let message = try? JSONDecoder().decode(ControlMessage.self, from: payload) else { return }
            emit(.message(message))
        case .fileChunk:
            guard let transferID = UUID(dataRepresentation: payload.prefix(16)) else { return }
            appendChunk(payload.dropFirst(16), to: transferID)
        case .fileEnd:
            guard let transferID = UUID(dataRepresentation: payload.prefix(16)) else { return }
            finishFile(transferID)
        }
    }

    private func appendChunk(_ chunk: Data, to transferID: UUID) {
        if incomingFiles[transferID] == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("airpro-\(transferID.uuidString)")
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

    private func terminate(with error: NWError?) {
        guard !hasTerminated else { return }
        hasTerminated = true
        isReady = false
        for incomingFile in incomingFiles.values {
            try? incomingFile.handle.close()
            try? FileManager.default.removeItem(at: incomingFile.url)
        }
        incomingFiles.removeAll()
        connection.cancel()
        emit(.closed(error))
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
