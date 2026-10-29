import Network
import Observation
import SwiftUI
import UIKit

struct DiscoveredMac: Identifiable, Equatable {
    let id: String
    let name: String
    let isAcceptingPairing: Bool
    let endpoint: NWEndpoint
}

@Observable
final class PhoneCoordinator {
    enum LinkState: Equatable {
        case searching
        case needsPairing
        case connecting
        case connected
    }

    var linkState: LinkState = .searching
    var connectedMacName: String?
    var pairedMacName: String?
    var pairingCandidates: [DiscoveredMac] = []
    var pairingErrorMessage: String?
    var isPairingInProgress = false
    var draggingItemURL: URL?
    var macSide: ScreenSide {
        didSet {
            UserDefaults.standard.set(macSide.rawValue, forKey: Self.macSideDefaultsKey)
            stage.peerSide = macSide
        }
    }

    let stage = TransferStage()
    let library = FileLibrary()

    @ObservationIgnored private static let macSideDefaultsKey = "airpro.macSide"
    @ObservationIgnored private let pairingStore = PairingStore()
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: PeerConnection?
    @ObservationIgnored private var connectionIsPairingAttempt = false
    @ObservationIgnored private var didCompletePairingOnConnection = false
    @ObservationIgnored private var recentPairingDate: Date?
    @ObservationIgnored private var discoveredMacs: [DiscoveredMac] = []
    @ObservationIgnored private var pendingIncoming: [UUID: TransferAnnouncement] = [:]
    @ObservationIgnored private var lastSentHover: (intensity: Double, verticalPosition: Double) = (0, 0.5)
    @ObservationIgnored private var reconnectWorkItem: DispatchWorkItem?
    @ObservationIgnored private var draggingTransferID: UUID?
    @ObservationIgnored private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    @ObservationIgnored private let notificationFeedback = UINotificationFeedbackGenerator()

    var isConnected: Bool { linkState == .connected }

    init() {
        macSide = ScreenSide(rawValue: UserDefaults.standard.string(forKey: Self.macSideDefaultsKey) ?? "") ?? .left
        pairedMacName = pairingStore.pairedPeer?.deviceName
        stage.peerSide = macSide
        stage.restingScale = 1.25
    }

    func activate() {
        library.reload()
        startBrowsing()
    }

    func deactivate() {
        reconnectWorkItem?.cancel()
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        connectedMacName = nil
        pendingIncoming.removeAll()
        linkState = .searching
        stage.abortAll()
    }

    func submitPairingCode(_ code: String, for mac: DiscoveredMac) {
        pairingErrorMessage = nil
        isPairingInProgress = true
        connect(to: mac, sharedSecret: Data(code.utf8), isPairingAttempt: true)
    }

    func forgetPairedMac() {
        pairingStore.pairedPeer = nil
        pairedMacName = nil
        connection?.cancel()
        connection = nil
        connectedMacName = nil
        linkState = .searching
        evaluateConnection()
    }

    func beginDragging(_ item: LibraryItem, at point: CGPoint) {
        let transferID = UUID()
        draggingTransferID = transferID
        draggingItemURL = item.url
        impactFeedback.impactOccurred()
        stage.beginDrag(id: transferID, thumbnail: library.thumbnails[item.url], fileName: item.name, at: point)
    }

    func moveDragging(to point: CGPoint) {
        guard let draggingTransferID else { return }
        stage.moveDrag(id: draggingTransferID, to: point)
        let proximity = stage.proximityToPeerEdge(of: point)
        let verticalPosition = stage.normalizedVerticalPosition(of: point)
        stage.showHover(intensity: proximity * 0.7, verticalPosition: verticalPosition)
        sendHover(intensity: isConnected ? proximity : 0, verticalPosition: verticalPosition)
    }

    func endDragging(_ item: LibraryItem, at point: CGPoint, predictedEnd: CGPoint, origin: CGPoint) {
        guard let transferID = draggingTransferID else { return }
        draggingTransferID = nil
        draggingItemURL = nil

        let flungTowardMac = macSide == .left ? predictedEnd.x < -40 : predictedEnd.x > stage.canvasSize.width + 40
        let reachedEdge = stage.proximityToPeerEdge(of: point) > 0.85
        guard let connection, isConnected, flungTowardMac || reachedEdge else {
            stage.cancelDrag(id: transferID, returningTo: origin)
            sendHover(intensity: 0, verticalPosition: lastSentHover.verticalPosition)
            return
        }
        send(item, transferID: transferID, via: connection, from: point)
    }

    func cancelDragging() {
        guard let transferID = draggingTransferID else { return }
        draggingTransferID = nil
        draggingItemURL = nil
        stage.cancelDrag(id: transferID, returningTo: CGPoint(x: stage.canvasSize.width / 2, y: stage.canvasSize.height / 2))
        sendHover(intensity: 0, verticalPosition: lastSentHover.verticalPosition)
    }

    private func send(_ item: LibraryItem, transferID: UUID, via connection: PeerConnection, from point: CGPoint) {
        let thumbnail = library.thumbnails[item.url]
        let announcement = TransferAnnouncement(
            id: transferID,
            fileName: item.name,
            byteCount: item.byteCount,
            thumbnailData: thumbnail.flatMap(ThumbnailRenderer.encodedData(from:)),
            verticalPosition: stage.normalizedVerticalPosition(of: point)
        )
        lastSentHover = (0, announcement.verticalPosition)
        impactFeedback.impactOccurred(intensity: 1)
        stage.launchOutgoing(id: transferID, thumbnail: thumbnail, fileName: item.name, from: point)
        connection.send(.transferStart(announcement))
        connection.sendFile(at: item.url, transferID: transferID) { succeeded in
            guard !succeeded else { return }
            connection.send(.transferFailed(id: transferID))
        }
    }

    private func sendHover(intensity: Double, verticalPosition: Double) {
        let intensityChanged = abs(intensity - lastSentHover.intensity) > 0.04 || (intensity == 0 && lastSentHover.intensity != 0)
        let positionMoved = abs(verticalPosition - lastSentHover.verticalPosition) > 0.03
        guard intensityChanged || (intensity > 0 && positionMoved) else { return }
        lastSentHover = (intensity, verticalPosition)
        connection?.send(.edgeHover(intensity: intensity, verticalPosition: verticalPosition))
    }

    private func startBrowsing() {
        guard browser == nil else { return }
        let newBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: AirProService.bonjourType, domain: nil),
            using: .airProDiscovery
        )
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.updateDiscoveredMacs(from: results)
        }
        newBrowser.stateUpdateHandler = { [weak self, weak newBrowser] state in
            guard case .failed = state else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, let newBrowser, self.browser === newBrowser else { return }
                self.browser = nil
                self.startBrowsing()
            }
        }
        newBrowser.start(queue: .main)
        browser = newBrowser
    }

    private func updateDiscoveredMacs(from results: Set<NWBrowser.Result>) {
        discoveredMacs = results
            .compactMap { result -> DiscoveredMac? in
                guard case .bonjour(let txtRecord) = result.metadata, let deviceID = txtRecord[AirProService.deviceIDKey] else {
                    return nil
                }
                var name = "Mac"
                if case .service(let serviceName, _, _, _) = result.endpoint {
                    name = serviceName
                }
                return DiscoveredMac(
                    id: deviceID,
                    name: name,
                    isAcceptingPairing: txtRecord[AirProService.modeKey] == AirProService.pairingModeValue,
                    endpoint: result.endpoint
                )
            }
            .sorted { $0.name < $1.name }
        evaluateConnection()
    }

    private func evaluateConnection() {
        guard connection == nil else { return }
        let pairedPeer = pairingStore.pairedPeer

        if let pairedPeer, let mac = discoveredMacs.first(where: { $0.id == pairedPeer.deviceID && !$0.isAcceptingPairing }) {
            connect(to: mac, sharedSecret: pairedPeer.sharedSecret, isPairingAttempt: false)
            return
        }

        if let recentPairingDate, Date().timeIntervalSince(recentPairingDate) < 6 {
            linkState = .connecting
            scheduleReconnect(after: 1)
            return
        }

        let candidates = discoveredMacs.filter(\.isAcceptingPairing)
        pairingCandidates = pairedPeer.map { peer in candidates.filter { $0.id == peer.deviceID } } ?? candidates
        linkState = pairingCandidates.isEmpty ? .searching : .needsPairing
    }

    private func connect(to mac: DiscoveredMac, sharedSecret: Data, isPairingAttempt: Bool) {
        reconnectWorkItem?.cancel()
        connection?.cancel()
        let peer = PeerConnection(endpoint: mac.endpoint, sharedSecret: sharedSecret)
        connection = peer
        connectionIsPairingAttempt = isPairingAttempt
        didCompletePairingOnConnection = false
        if !isPairingAttempt {
            linkState = .connecting
        }
        peer.onEvent = { [weak self, weak peer] event in
            guard let self, let peer, peer === self.connection else { return }
            self.handle(event, from: peer)
        }
        peer.start()
    }

    private func handle(_ event: PeerEvent, from peer: PeerConnection) {
        switch event {
        case .ready:
            if !connectionIsPairingAttempt {
                linkState = .connected
            }
            peer.send(.hello(deviceName: UIDevice.current.name))
        case .closed:
            handleConnectionClosed()
        case .message(let message):
            handle(message)
        case .bytesReceived(let transferID, let totalBytes):
            guard let announcement = pendingIncoming[transferID], announcement.byteCount > 0 else { return }
            stage.updateProgress(id: transferID, progress: Double(totalBytes) / Double(announcement.byteCount))
        case .fileReceived(let transferID, let temporaryURL):
            let fileName = pendingIncoming.removeValue(forKey: transferID)?.fileName ?? "File"
            library.adoptReceivedFile(at: temporaryURL, named: fileName)
            stage.finishIncoming(id: transferID)
            notificationFeedback.notificationOccurred(.success)
        }
    }

    private func handleConnectionClosed() {
        let pairingFailed = connectionIsPairingAttempt && !didCompletePairingOnConnection
        connection = nil
        connectedMacName = nil
        pendingIncoming.removeAll()
        connectionIsPairingAttempt = false
        draggingItemURL = nil
        draggingTransferID = nil
        stage.abortAll()

        if pairingFailed {
            isPairingInProgress = false
            pairingErrorMessage = "That code didn't match. Try again."
            notificationFeedback.notificationOccurred(.error)
        }
        linkState = .searching
        scheduleReconnect(after: pairingFailed ? 0 : 1.5)
    }

    private func scheduleReconnect(after delay: TimeInterval) {
        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.evaluateConnection()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func handle(_ message: ControlMessage) {
        switch message {
        case .hello(let deviceName):
            connectedMacName = deviceName
        case .pairingComplete(let sharedSecret, let deviceID, let deviceName):
            pairingStore.pairedPeer = PairedPeer(deviceID: deviceID, deviceName: deviceName, sharedSecret: sharedSecret)
            pairedMacName = deviceName
            didCompletePairingOnConnection = true
            recentPairingDate = Date()
            isPairingInProgress = false
            pairingErrorMessage = nil
            pairingCandidates = []
            linkState = .connecting
            notificationFeedback.notificationOccurred(.success)
        case .edgeHover(let intensity, let verticalPosition):
            stage.showHover(intensity: intensity, verticalPosition: verticalPosition)
        case .transferStart(let announcement):
            pendingIncoming[announcement.id] = announcement
            impactFeedback.impactOccurred()
            stage.receiveIncoming(
                id: announcement.id,
                thumbnail: ThumbnailRenderer.image(from: announcement.thumbnailData),
                fileName: announcement.fileName,
                verticalPosition: announcement.verticalPosition
            )
        case .transferFailed(let transferID):
            pendingIncoming[transferID] = nil
            stage.abortAll()
        }
    }
}
