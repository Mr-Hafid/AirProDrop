import AppKit
import SwiftUI

final class OverlayWindowController {
    var onDragHover: ((Bool, CGPoint) -> Void)?
    var onDrop: (([URL], CGPoint) -> Void)?
    var phoneSide: ScreenSide {
        didSet { layoutWindows() }
    }

    private let stage: TransferStage
    private let overlayWindow: NSWindow
    private let dropWindow: NSWindow
    private let dropView = EdgeDropView()
    private let edgeStripWidth: CGFloat = 4
    private var screenObserver: NSObjectProtocol?

    init(stage: TransferStage, phoneSide: ScreenSide) {
        self.stage = stage
        self.phoneSide = phoneSide

        overlayWindow = Self.makeTransparentWindow()
        overlayWindow.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: OverlayView(stage: stage))
        hostingView.sizingOptions = []
        overlayWindow.contentView = hostingView

        dropWindow = Self.makeTransparentWindow()
        dropWindow.contentView = dropView

        dropView.onHoverChange = { [weak self] isHovering in
            self?.onDragHover?(isHovering, NSEvent.mouseLocation)
        }
        dropView.onDrop = { [weak self] urls in
            self?.onDrop?(urls, NSEvent.mouseLocation)
        }

        layoutWindows()
        overlayWindow.orderFrontRegardless()
        dropWindow.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layoutWindows()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func layoutWindows() {
        guard let frame = targetScreen?.frame else { return }
        overlayWindow.setFrame(frame, display: true)
        stage.canvasSize = frame.size
        stage.peerSide = phoneSide

        let stripX = phoneSide == .right ? frame.maxX - edgeStripWidth : frame.minX
        dropWindow.setFrame(NSRect(x: stripX, y: frame.minY, width: edgeStripWidth, height: frame.height), display: true)
    }

    func stagePoint(fromScreenPoint screenPoint: CGPoint) -> CGPoint {
        guard let frame = targetScreen?.frame else { return screenPoint }
        return CGPoint(x: screenPoint.x - frame.minX, y: frame.maxY - screenPoint.y)
    }

    private static func makeTransparentWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}

private struct OverlayView: View {
    let stage: TransferStage

    var body: some View {
        ZStack {
            EdgeGlow(
                intensity: stage.glowIntensity,
                side: stage.peerSide,
                verticalPosition: stage.glowVerticalPosition,
                waveStartDate: stage.waveStartDate
            )
            FlyingCardLayer(cards: stage.cards)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private extension NSScreen {
    var isBuiltIn: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber.uint32Value) != 0
    }
}
