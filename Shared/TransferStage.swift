import Observation
import SwiftUI

@Observable
final class TransferStage {
    var canvasSize: CGSize = CGSize(width: 1, height: 1)
    var peerSide: ScreenSide = .right
    var glowIntensity = 0.0
    var glowVerticalPosition = 0.5
    var waveStartDate: Date?
    var cards: [FlyingCard] = []

    @ObservationIgnored var restingScale: CGFloat = 1.2
    @ObservationIgnored private var activeFlightIDs: Set<UUID> = []

    var isBusy: Bool { !activeFlightIDs.isEmpty }

    func showHover(intensity: Double, verticalPosition: Double) {
        guard activeFlightIDs.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            glowIntensity = min(max(intensity, 0), 1)
            glowVerticalPosition = verticalPosition
        }
    }

    func beginDrag(id: UUID, thumbnail: CGImage?, fileName: String, at point: CGPoint) {
        cards.removeAll { $0.id == id }
        cards.append(FlyingCard(id: id, thumbnail: thumbnail, fileName: fileName, position: point, scale: 0.9, opacity: 1))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            updateCard(id) { $0.scale = 1.05 }
        }
    }

    func moveDrag(id: UUID, to point: CGPoint) {
        updateCard(id) {
            $0.position = point
            $0.rotation = rotationTowardPeer(for: point) * 0.5
        }
    }

    func cancelDrag(id: UUID, returningTo point: CGPoint) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            updateCard(id) {
                $0.position = point
                $0.scale = 0.9
                $0.opacity = 0
                $0.rotation = 0
            }
            glowIntensity = 0
        }
        removeCard(id, after: 0.35)
    }

    func launchOutgoing(id: UUID, thumbnail: CGImage?, fileName: String, from start: CGPoint) {
        activeFlightIDs.insert(id)
        if !cards.contains(where: { $0.id == id }) {
            cards.append(FlyingCard(id: id, thumbnail: thumbnail, fileName: fileName, position: start, scale: restingScale * 0.8, opacity: 1))
        }
        waveStartDate = Date()
        withAnimation(.easeOut(duration: 0.2)) {
            glowIntensity = 1
            glowVerticalPosition = normalizedVerticalPosition(of: start)
        }
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: 0.42)) {
                self.updateCard(id) {
                    $0.position = self.offscreenPoint(atY: start.y)
                    $0.scale = 0.5
                    $0.rotation = self.peerSide == .right ? 10 : -10
                }
            }
        }
        removeCard(id, after: 0.45)
        endFlight(id, after: 0.55)
    }

    func receiveIncoming(id: UUID, thumbnail: CGImage?, fileName: String, verticalPosition: Double) {
        activeFlightIDs.insert(id)
        let clampedPosition = min(max(verticalPosition, 0.15), 0.85)
        let entryPoint = offscreenPoint(atY: canvasSize.height * clampedPosition)
        cards.removeAll { $0.id == id }
        cards.append(
            FlyingCard(
                id: id,
                thumbnail: thumbnail,
                fileName: fileName,
                position: entryPoint,
                scale: 0.5,
                opacity: 1,
                rotation: peerSide == .right ? -10 : 10,
                progress: 0
            )
        )
        waveStartDate = Date()
        withAnimation(.easeOut(duration: 0.25)) {
            glowIntensity = 1
            glowVerticalPosition = clampedPosition
        }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
                self.updateCard(id) {
                    $0.position = CGPoint(x: self.canvasSize.width / 2, y: self.canvasSize.height / 2)
                    $0.scale = self.restingScale
                    $0.rotation = 0
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard self.activeFlightIDs.contains(id) else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                self.glowIntensity = 0.4
            }
        }
    }

    func updateProgress(id: UUID, progress: Double) {
        updateCard(id) { $0.progress = min(max(progress, 0), 1) }
    }

    func finishIncoming(id: UUID) {
        updateCard(id) { $0.progress = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.35)) {
                self.updateCard(id) {
                    $0.scale = self.restingScale * 0.85
                    $0.opacity = 0
                }
            }
            self.removeCard(id, after: 0.4)
            self.endFlight(id, after: 0)
        }
    }

    func abortAll() {
        activeFlightIDs.removeAll()
        withAnimation(.easeOut(duration: 0.3)) {
            for index in cards.indices {
                cards[index].opacity = 0
            }
            glowIntensity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.cards.removeAll()
        }
    }

    func proximityToPeerEdge(of point: CGPoint) -> Double {
        let distanceToEdge = peerSide == .left ? point.x : canvasSize.width - point.x
        let activationWidth = canvasSize.width * 0.6
        return min(max(1 - distanceToEdge / activationWidth, 0), 1)
    }

    func normalizedVerticalPosition(of point: CGPoint) -> Double {
        guard canvasSize.height > 0 else { return 0.5 }
        return min(max(point.y / canvasSize.height, 0), 1)
    }

    private func offscreenPoint(atY y: CGFloat) -> CGPoint {
        CGPoint(x: peerSide == .left ? -220 : canvasSize.width + 220, y: y)
    }

    private func rotationTowardPeer(for point: CGPoint) -> Double {
        let direction: Double = peerSide == .right ? 1 : -1
        return direction * proximityToPeerEdge(of: point) * 12
    }

    private func updateCard(_ id: UUID, _ change: (inout FlyingCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[index])
    }

    private func removeCard(_ id: UUID, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.cards.removeAll { $0.id == id }
        }
    }

    private func endFlight(_ id: UUID, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.activeFlightIDs.remove(id)
            guard self.activeFlightIDs.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                self.glowIntensity = 0
            }
        }
    }
}
