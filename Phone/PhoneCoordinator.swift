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
    var trustedMacs: [TrustedDevice] = []
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
    @ObservationIgnored private let identity = DeviceIdentity.loadOrCreate()
    @ObservationIgnored private let trustStore = TrustStore()
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: PeerConnection?
    @ObservationIgnored private var connectingMac: DiscoveredMac?
    @ObservationIgnored private var connectionIsPairingAttempt = false
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
        trustedMacs = trustStore.devices
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
        connectingMac = nil
        connectedMacName = nil
        pendingIncoming.removeAll()
        linkState = .searching
        stage.abortAll()
    }

    func submitPairingCode(_ code: String, for mac: DiscoveredMac) {
        guard let passkey = Int(code) else { return }
        pairingErrorMessage = nil
        isPairingInProgress = true
        connect(to: mac, role: .pair(passkey: passkey))
    }

    func forget(_ mac: TrustedDevice) {
        trustStore.forget(deviceID: mac.deviceID)
        trustedMacs = trustStore.devices
        guard connectingMac?.id == mac.deviceID else {
            evaluateConnection()
            return
        }
        connection?.cancel()
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
        pairingCandidates = discoveredMacs.filter { trustStore.device(withID: $0.id) == nil }
        evaluateConnection()
    }

    private func evaluateConnection() {
        pairingCandidates = discoveredMacs.filter { trustStore.device(withID: $0.id) == nil }
        guard connection == nil else { return }

        let nearbyTrustedMacs = discoveredMacs
            .compactMap { mac in trustStore.device(withID: mac.id).map { (mac, $0) } }
            .sorted { $0.1.lastConnected > $1.1.lastConnected }
        if let (mac, trustedMac) = nearbyTrustedMacs.first {
            connect(to: mac, role: .resume(expectedIdentityKey: trustedMac.identityKey))
            return
        }
        linkState = pairingCandidates.isEmpty ? .searching : .needsPairing
    }

    private func connect(to mac: DiscoveredMac, role: HandshakeRole) {
        reconnectWorkItem?.cancel()
        connection?.cancel()
        let handshake = SecureHandshake(role: role, identity: identity, deviceID: LocalDevice.identifier, deviceName: UIDevice.current.name)
        let peer = PeerConnection(endpoint: mac.endpoint, handshake: handshake)
        connection = peer
        connectingMac = mac
        if case .pair = role {
            connectionIsPairingAttempt = true
        } else {
            connectionIsPairingAttempt = false
            linkState = .connecting
        }
        peer.onEvent = { [weak self, weak peer] event in
            guard let self, let peer, peer === self.connection else { return }
            self.handle(event)
        }
        peer.start()
    }

    private func handle(_ event: PeerEvent) {
        switch event {
        case .ready(let info):
            handleSecureConnection(with: info)
        case .closed(let failure):
            handleConnectionClosed(failure)
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

    private func handleSecureConnection(with info: PeerInfo) {
        if info.didPair {
            trustStore.trust(info)
            isPairingInProgress = false
            pairingErrorMessage = nil
            notificationFeedback.notificationOccurred(.success)
        } else {
            trustStore.recordConnection(with: info)
        }
        trustedMacs = trustStore.devices
        pairingCandidates = discoveredMacs.filter { trustStore.device(withID: $0.id) == nil }
        connectionIsPairingAttempt = false
        connectedMacName = info.deviceName
        linkState = .connected
    }

    private func handleConnectionClosed(_ failure: PeerFailure?) {
        let wasPairingAttempt = connectionIsPairingAttempt
        let closedMac = connectingMac
        connection = nil
        connectingMac = nil
        connectedMacName = nil
        pendingIncoming.removeAll()
        connectionIsPairingAttempt = false
        draggingItemURL = nil
        draggingTransferID = nil
        stage.abortAll()

        if wasPairingAttempt {
            isPairingInProgress = false
            pairingErrorMessage = pairingErrorMessage(for: failure)
            notificationFeedback.notificationOccurred(.error)
        } else if failure == .untrusted, let closedMac {
            trustStore.forget(deviceID: closedMac.id)
            trustedMacs = trustStore.devices
        }
        linkState = .searching
        scheduleReconnect(after: wasPairingAttempt ? 0 : 1.5)
    }

    private func pairingErrorMessage(for failure: PeerFailure?) -> String {
        switch failure {
        case .passkeyMismatch:
            return "That code didn't match. Check the code on your Mac and try again."
        case .notAcceptingPairing:
            return "Click Pair New iPhone in the AirProDrop menu on your Mac first."
        default:
            return "Couldn't connect. Make sure Wi-Fi is on and try again."
        }
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
