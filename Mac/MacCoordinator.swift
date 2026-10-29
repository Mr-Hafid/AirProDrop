import AppKit
import Network
import Observation

@Observable
final class MacCoordinator {
    var pairingCode: String?
    var connectedPhoneName: String?
    var pairedPhoneName: String?
    var phoneSide: ScreenSide {
        didSet {
            UserDefaults.standard.set(phoneSide.rawValue, forKey: Self.phoneSideDefaultsKey)
            overlay?.phoneSide = phoneSide
        }
    }

    let stage = TransferStage()

    @ObservationIgnored private static let phoneSideDefaultsKey = "airpro.phoneSide"
    @ObservationIgnored private let pairingStore = PairingStore()
    @ObservationIgnored private let receivedFileNotifier = ReceivedFileNotifier()
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connection: PeerConnection?
    @ObservationIgnored private var handshakingConnections: [ObjectIdentifier: PeerConnection] = [:]
    @ObservationIgnored private var overlay: OverlayWindowController?
    @ObservationIgnored private var pendingIncoming: [UUID: TransferAnnouncement] = [:]
    @ObservationIgnored private var lastSentHover: (intensity: Double, verticalPosition: Double) = (0, 0.5)

    var receivedFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    private var macName: String {
        Host.current().localizedName ?? "Mac"
    }

    init() {
        phoneSide = ScreenSide(rawValue: UserDefaults.standard.string(forKey: Self.phoneSideDefaultsKey) ?? "") ?? .right
        pairedPhoneName = pairingStore.pairedPeer?.deviceName
        stage.peerSide = phoneSide
        stage.restingScale = 1.7
    }

    func start() {
        let overlay = OverlayWindowController(stage: stage, phoneSide: phoneSide)
        overlay.onDragHover = { [weak self] isHovering, screenPoint in
            self?.handleDragHover(isHovering, at: screenPoint)
        }
        overlay.onDrop = { [weak self] urls, screenPoint in
            self?.send(urls, from: screenPoint)
        }
        self.overlay = overlay
        receivedFileNotifier.start()
        startListening()
    }

    func pairNewPhone() {
        pairingStore.pairedPeer = nil
        pairedPhoneName = nil
        connection?.cancel()
        startListening()
    }

    func chooseFilesToSend() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.send(panel.urls, from: nil)
        }
    }

    func openReceivedFolder() {
        try? FileManager.default.createDirectory(at: receivedFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(receivedFolder)
    }

    private func startListening() {
        listener?.cancel()
        listener = nil

        let pairedPeer = pairingStore.pairedPeer
        let sharedSecret: Data
        let mode: String
        if let pairedPeer {
            sharedSecret = pairedPeer.sharedSecret
            mode = AirProService.pairedModeValue
            pairingCode = nil
        } else {
            let code = PairingStore.makePairingCode()
            sharedSecret = Data(code.utf8)
            mode = AirProService.pairingModeValue
            pairingCode = code
        }

        guard let newListener = try? NWListener(using: .airPro(sharedSecret: sharedSecret)) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startListening() }
            return
        }
        let txtRecord = NWTXTRecord([
            AirProService.modeKey: mode,
            AirProService.deviceIDKey: LocalDevice.identifier
        ])
        newListener.service = NWListener.Service(name: macName, type: AirProService.bonjourType, domain: nil, txtRecord: txtRecord.data)
        let isPairingListener = pairedPeer == nil
        newListener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection, isPairing: isPairingListener)
        }
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard case .failed = state else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, let newListener, self.listener === newListener else { return }
                self.startListening()
            }
        }
        newListener.start(queue: .main)
        listener = newListener
    }

    private func accept(_ newConnection: NWConnection, isPairing: Bool) {
        let peer = PeerConnection(connection: newConnection)
        let peerID = ObjectIdentifier(peer)
        handshakingConnections[peerID] = peer
        peer.onEvent = { [weak self, weak peer] event in
            guard let self, let peer else { return }
            self.handle(event, from: peer, isPairing: isPairing)
        }
        peer.start()
    }

    private func handle(_ event: PeerEvent, from peer: PeerConnection, isPairing: Bool) {
        let peerID = ObjectIdentifier(peer)
        if handshakingConnections[peerID] != nil {
            switch event {
            case .ready:
                handshakingConnections[peerID] = nil
                promote(peer, isPairing: isPairing)
            case .closed:
                handshakingConnections[peerID] = nil
            default:
                break
            }
            return
        }
        guard peer === connection else { return }

        switch event {
        case .ready:
            break
        case .closed:
            connection = nil
            connectedPhoneName = nil
            pendingIncoming.removeAll()
            stage.abortAll()
        case .message(let message):
            handle(message)
        case .bytesReceived(let transferID, let totalBytes):
            guard let announcement = pendingIncoming[transferID], announcement.byteCount > 0 else { return }
            stage.updateProgress(id: transferID, progress: Double(totalBytes) / Double(announcement.byteCount))
        case .fileReceived(let transferID, let temporaryURL):
            let announcement = pendingIncoming.removeValue(forKey: transferID)
            stage.finishIncoming(id: transferID)
            storeReceivedFile(at: temporaryURL, named: announcement?.fileName ?? "File", thumbnailData: announcement?.thumbnailData)
        }
    }

    private func promote(_ peer: PeerConnection, isPairing: Bool) {
        connection?.cancel()
        connection = peer
        peer.send(.hello(deviceName: macName))
        guard isPairing else { return }

        let sharedSecret = PairingStore.makeSharedSecret()
        peer.send(.pairingComplete(sharedSecret: sharedSecret, deviceID: LocalDevice.identifier, deviceName: macName)) { [weak self] in
            guard let self else { return }
            let phoneName = self.connectedPhoneName ?? "iPhone"
            self.pairingStore.pairedPeer = PairedPeer(deviceID: "", deviceName: phoneName, sharedSecret: sharedSecret)
            self.pairedPhoneName = phoneName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                peer.cancel()
                self.startListening()
            }
        }
    }

    private func handle(_ message: ControlMessage) {
        switch message {
        case .hello(let deviceName):
            connectedPhoneName = deviceName
            if var pairedPeer = pairingStore.pairedPeer, pairedPeer.deviceName != deviceName {
                pairedPeer.deviceName = deviceName
                pairingStore.pairedPeer = pairedPeer
                pairedPhoneName = deviceName
            }
        case .edgeHover(let intensity, let verticalPosition):
            stage.showHover(intensity: intensity, verticalPosition: verticalPosition)
        case .transferStart(let announcement):
            pendingIncoming[announcement.id] = announcement
            stage.receiveIncoming(
                id: announcement.id,
                thumbnail: ThumbnailRenderer.image(from: announcement.thumbnailData),
                fileName: announcement.fileName,
                verticalPosition: announcement.verticalPosition
            )
        case .transferFailed(let transferID):
            pendingIncoming[transferID] = nil
            stage.abortAll()
        case .pairingComplete:
            break
        }
    }

    private func storeReceivedFile(at temporaryURL: URL, named fileName: String, thumbnailData: Data?) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: receivedFolder, withIntermediateDirectories: true)
        let destination = fileManager.uniqueDestination(forFileNamed: fileName, in: receivedFolder)
        do {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            return
        }
        receivedFileNotifier.notifyReceived(fileAt: destination, from: connectedPhoneName ?? "iPhone", thumbnailData: thumbnailData)
        guard ReceivedFileNotifier.isMedia(destination) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.open(destination)
        }
    }

    private func handleDragHover(_ isHovering: Bool, at screenPoint: CGPoint) {
        guard let overlay else { return }
        let verticalPosition = stage.normalizedVerticalPosition(of: overlay.stagePoint(fromScreenPoint: screenPoint))
        let intensity = isHovering && connection != nil ? 0.75 : 0
        stage.showHover(intensity: intensity, verticalPosition: verticalPosition)

        let intensityChanged = intensity != lastSentHover.intensity
        let positionMoved = abs(verticalPosition - lastSentHover.verticalPosition) > 0.03
        guard intensityChanged || (intensity > 0 && positionMoved) else { return }
        lastSentHover = (intensity, verticalPosition)
        connection?.send(.edgeHover(intensity: intensity, verticalPosition: verticalPosition))
    }

    private func send(_ urls: [URL], from screenPoint: CGPoint?) {
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        lastSentHover = (0, lastSentHover.verticalPosition)
        guard let connection, let overlay, !files.isEmpty else {
            stage.showHover(intensity: 0, verticalPosition: 0.5)
            NSSound.beep()
            return
        }

        let launchPoint = launchPoint(for: screenPoint.map(overlay.stagePoint(fromScreenPoint:)))
        for (index, url) in files.enumerated() {
            let offsetPoint = CGPoint(x: launchPoint.x, y: launchPoint.y + CGFloat(index) * 24)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.3) {
                Task { @MainActor in
                    await self.sendFile(at: url, via: connection, from: offsetPoint)
                }
            }
        }
    }

    private func launchPoint(for stagePoint: CGPoint?) -> CGPoint {
        let canvas = stage.canvasSize
        let inset: CGFloat = 280
        let x = phoneSide == .right ? canvas.width - inset : inset
        let y = stagePoint?.y ?? canvas.height / 2
        return CGPoint(x: x, y: min(max(y, 160), canvas.height - 160))
    }

    @MainActor
    private func sendFile(at url: URL, via connection: PeerConnection, from point: CGPoint) async {
        let thumbnail = await ThumbnailRenderer.image(for: url)
        let transferID = UUID()
        let byteCount = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let announcement = TransferAnnouncement(
            id: transferID,
            fileName: url.lastPathComponent,
            byteCount: byteCount,
            thumbnailData: thumbnail.flatMap(ThumbnailRenderer.encodedData(from:)),
            verticalPosition: stage.normalizedVerticalPosition(of: point)
        )
        stage.launchOutgoing(id: transferID, thumbnail: thumbnail, fileName: url.lastPathComponent, from: point)
        connection.send(.transferStart(announcement))
        connection.sendFile(at: url, transferID: transferID) { succeeded in
            guard !succeeded else { return }
            connection.send(.transferFailed(id: transferID))
        }
    }
}
