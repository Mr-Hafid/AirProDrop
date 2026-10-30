import Network
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let byteCount: Int64
    var thumbnail: CGImage?
}

@Observable
final class ShareCoordinator {
    enum Phase: Equatable {
        case preparing
        case searching
        case noTrustedMac
        case ready
        case sending
        case sent
        case failed(String)
    }

    var phase = Phase.preparing
    var files: [SharedFile] = []
    var macName: String?
    var isLoadingFiles = true
    var launchOrigin: CGPoint?
    let macSide: ScreenSide
    let stage = TransferStage()

    var canSend: Bool {
        phase == .ready && !isLoadingFiles && !files.isEmpty
    }

    @ObservationIgnored private let onFinish: () -> Void
    @ObservationIgnored private let onCancel: () -> Void
    @ObservationIgnored private let identity = DeviceIdentity.loadOrCreate()
    @ObservationIgnored private let trustStore = TrustStore()
    @ObservationIgnored private let workingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("airprodrop-share-\(UUID().uuidString)", isDirectory: true)
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: PeerConnection?
    @ObservationIgnored private var isAutoSendArmed = false
    @ObservationIgnored private var lastSentHover: (intensity: Double, verticalPosition: Double) = (0, 0.5)
    @ObservationIgnored private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    @ObservationIgnored private let notificationFeedback = UINotificationFeedbackGenerator()

    init(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        macSide = ScreenSide(rawValue: SharedContainer.string(forKey: SharedContainer.macSideDefaultsKey) ?? "") ?? .left
        stage.peerSide = macSide
        stage.restingScale = 1.1
    }

    func start(with inputItems: [NSExtensionItem]) {
        let providers = inputItems.flatMap { $0.attachments ?? [] }
        Task { @MainActor in
            await loadFiles(from: providers)
        }
        if trustStore.devices.isEmpty {
            phase = .noTrustedMac
            return
        }
        phase = .searching
        startBrowsing()
    }

    func armAutoSend() {
        isAutoSendArmed = true
        sendAutomaticallyIfReady()
    }

    func cancel() {
        tearDown()
        onCancel()
    }

    func moveDragging(id: UUID, to point: CGPoint) {
        stage.moveDrag(id: id, to: point)
        let proximity = stage.proximityToPeerEdge(of: point)
        let verticalPosition = stage.normalizedVerticalPosition(of: point)
        stage.showHover(intensity: proximity * 0.7, verticalPosition: verticalPosition)
        sendHover(intensity: phase == .ready ? proximity : 0, verticalPosition: verticalPosition)
    }

    func endDragging(id: UUID, at point: CGPoint, predictedEnd: CGPoint, origin: CGPoint) {
        let flungTowardMac = macSide == .left ? predictedEnd.x < -40 : predictedEnd.x > stage.canvasSize.width + 40
        let reachedEdge = stage.proximityToPeerEdge(of: point) > 0.85
        guard canSend, flungTowardMac || reachedEdge else {
            stage.cancelDrag(id: id, returningTo: origin)
            sendHover(intensity: 0, verticalPosition: lastSentHover.verticalPosition)
            return
        }
        send(leadTransferID: id, from: point)
    }

    func send(leadTransferID: UUID = UUID(), from point: CGPoint) {
        guard canSend, let connection else { return }
        isAutoSendArmed = false
        phase = .sending
        lastSentHover = (0, stage.normalizedVerticalPosition(of: point))
        impactFeedback.impactOccurred(intensity: 1)

        let transferIDs = files.indices.map { $0 == 0 ? leadTransferID : UUID() }
        var remainingTransfers = files.count
        var allSucceeded = true
        for (index, file) in files.enumerated() {
            let transferID = transferIDs[index]
            let launchPoint = CGPoint(x: point.x, y: point.y + CGFloat(index) * 18)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.25) {
                let announcement = TransferAnnouncement(
                    id: transferID,
                    fileName: file.name,
                    byteCount: file.byteCount,
                    thumbnailData: file.thumbnail.flatMap(ThumbnailRenderer.encodedData(from:)),
                    verticalPosition: self.stage.normalizedVerticalPosition(of: launchPoint)
                )
                self.stage.launchOutgoing(id: transferID, thumbnail: file.thumbnail, fileName: file.name, from: launchPoint)
                connection.send(.transferStart(announcement))
                connection.sendFile(at: file.url, transferID: transferID) { succeeded in
                    if !succeeded {
                        allSucceeded = false
                        connection.send(.transferFailed(id: transferID))
                    }
                    remainingTransfers -= 1
                    guard remainingTransfers == 0 else { return }
                    self.finishSending(succeeded: allSucceeded)
                }
            }
        }
    }

    private func sendAutomaticallyIfReady() {
        guard isAutoSendArmed, canSend else { return }
        let origin = launchOrigin ?? CGPoint(x: stage.canvasSize.width / 2, y: stage.canvasSize.height / 2)
        send(from: origin)
    }

    private func finishSending(succeeded: Bool) {
        guard succeeded else {
            phase = .failed("Couldn't finish sending. Keep this open until the transfer is done.")
            notificationFeedback.notificationOccurred(.error)
            return
        }
        phase = .sent
        notificationFeedback.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.tearDown()
            self.onFinish()
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
        let newBrowser = NWBrowser(
            for: .bonjourWithTXTRecord(type: AirProService.bonjourType, domain: nil),
            using: .airProDiscovery
        )
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.connectToNearestTrustedMac(in: results)
        }
        newBrowser.start(queue: .main)
        browser = newBrowser
    }

    private func connectToNearestTrustedMac(in results: Set<NWBrowser.Result>) {
        guard connection == nil, phase == .searching else { return }
        let nearbyTrustedMacs = results
            .compactMap { result -> (NWEndpoint, TrustedDevice)? in
                guard case .bonjour(let txtRecord) = result.metadata,
                      let deviceID = txtRecord[AirProService.deviceIDKey],
                      let trustedMac = trustStore.device(withID: deviceID) else { return nil }
                return (result.endpoint, trustedMac)
            }
            .sorted { $0.1.lastConnected > $1.1.lastConnected }
        guard let (endpoint, trustedMac) = nearbyTrustedMacs.first else { return }

        let handshake = SecureHandshake(
            role: .resume(expectedIdentityKey: trustedMac.identityKey),
            identity: identity,
            deviceID: LocalDevice.identifier,
            deviceName: UIDevice.current.name
        )
        let peer = PeerConnection(endpoint: endpoint, handshake: handshake)
        connection = peer
        macName = trustedMac.name
        peer.onEvent = { [weak self, weak peer] event in
            guard let self, let peer, peer === self.connection else { return }
            self.handle(event)
        }
        peer.start()
    }

    private func handle(_ event: PeerEvent) {
        switch event {
        case .ready(let info):
            trustStore.recordConnection(with: info)
            macName = info.deviceName
            phase = .ready
            sendAutomaticallyIfReady()
        case .closed:
            connection = nil
            guard phase == .ready || phase == .searching || phase == .sending else { return }
            if phase == .sending {
                stage.abortAll()
                phase = .failed("Lost connection to your Mac. Try again.")
                return
            }
            phase = .searching
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let browser = self.browser else { return }
                self.connectToNearestTrustedMac(in: browser.browseResults)
            }
        case .message(let message):
            guard case .edgeHover(let intensity, let verticalPosition) = message, phase == .ready else { return }
            stage.showHover(intensity: intensity, verticalPosition: verticalPosition)
        case .pairingCodeDisplayed, .bytesReceived, .fileReceived:
            break
        }
    }

    @MainActor
    private func loadFiles(from providers: [NSItemProvider]) async {
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        var loadedFiles: [SharedFile] = []
        for provider in providers {
            guard let file = await copySharedFile(from: provider) else { continue }
            loadedFiles.append(file)
        }
        if !loadedFiles.isEmpty {
            loadedFiles[0].thumbnail = await ThumbnailRenderer.image(for: loadedFiles[0].url)
        }
        files = loadedFiles
        isLoadingFiles = false
        sendAutomaticallyIfReady()
        for index in files.indices.dropFirst() {
            let thumbnail = await ThumbnailRenderer.image(for: files[index].url)
            guard index < files.count else { return }
            files[index].thumbnail = thumbnail
        }
    }

    private func copySharedFile(from provider: NSItemProvider) async -> SharedFile? {
        let preferredTypes: [UTType] = [.movie, .image, .audio, .pdf, .data, .item]
        let registeredTypes = provider.registeredTypeIdentifiers.compactMap(UTType.init)
        guard let type = preferredTypes.lazy.compactMap({ preferred in registeredTypes.first { $0.conforms(to: preferred) } }).first else {
            return nil
        }
        let destinationDirectory = workingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suggestedName = provider.suggestedName

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let fileManager = FileManager.default
                var fileName = url.lastPathComponent
                if let suggestedName, !suggestedName.isEmpty {
                    let pathExtension = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "") : url.pathExtension
                    fileName = pathExtension.isEmpty || suggestedName.hasSuffix(".\(pathExtension)") ? suggestedName : "\(suggestedName).\(pathExtension)"
                }
                let destination = destinationDirectory.appendingPathComponent(fileName)
                do {
                    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                    try fileManager.copyItem(at: url, to: destination)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let byteCount = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                continuation.resume(returning: SharedFile(url: destination, name: fileName, byteCount: byteCount))
            }
        }
    }

    private func tearDown() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        try? FileManager.default.removeItem(at: workingDirectory)
    }
}
