import AppKit
import SwiftUI

final class PairingCodePanelController {
    private let panel: NSPanel

    init(coordinator: MacCoordinator) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        let hostingController = NSHostingController(rootView: PairingCodePanelView(coordinator: coordinator))
        hostingController.sizingOptions = .preferredContentSize
        panel.contentViewController = hostingController
    }

    func show() {
        if !panel.isVisible {
            placeAtTopCenter()
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func placeAtTopCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.maxY - size.height - 16))
    }
}

private struct PairingCodePanelView: View {
    let coordinator: MacCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("\(coordinator.pairingRequesterName ?? "iPhone") wants to pair")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("Enter this code on your iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(coordinator.formattedPairingCode ?? "")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: coordinator.pairingCode)
                .textSelection(.enabled)
            if let pairingExpiresAt = coordinator.pairingExpiresAt {
                Text("Expires \(pairingExpiresAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: coordinator.closePairingWindow)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 300)
    }
}
