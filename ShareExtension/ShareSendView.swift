import SwiftUI

struct ShareSendView: View {
    let coordinator: ShareCoordinator

    @State private var isLifted = false
    @State private var isHelpVisible = false
    @State private var draggingTransferID: UUID?

    private let canvasSpace = "shareCanvas"
    private let helpDelay: TimeInterval = 3.5

    private var isTransferring: Bool {
        coordinator.phase == .sending || coordinator.phase == .sent
    }

    private var needsHelpImmediately: Bool {
        switch coordinator.phase {
        case .noTrustedMac, .failed:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isTransferring ? 0 : 0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            EdgeGlow(
                intensity: coordinator.stage.glowIntensity,
                side: coordinator.macSide,
                verticalPosition: coordinator.stage.glowVerticalPosition,
                waveStartDate: coordinator.stage.waveStartDate
            )

            liftedFiles

            if isHelpVisible || needsHelpImmediately {
                VStack {
                    Spacer()
                    helpPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .transition(.liquidPanel)
            }

            FlyingCardLayer(cards: coordinator.stage.cards)
        }
        .coordinateSpace(name: canvasSpace)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            coordinator.stage.canvasSize = size
        }
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: isHelpVisible || needsHelpImmediately)
        .animation(.easeOut(duration: 0.3), value: isTransferring)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                isLifted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                coordinator.armAutoSend()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + helpDelay) {
                guard !isTransferring else { return }
                isHelpVisible = true
            }
        }
    }

    private var liftedFiles: some View {
        ZStack {
            ForEach(Array(coordinator.files.prefix(3).enumerated().reversed()), id: \.element.id) { index, file in
                ThumbnailCard(thumbnail: file.thumbnail, fileName: file.name, width: 220)
                    .rotationEffect(.degrees(Double(index) * (coordinator.macSide == .left ? -6 : 6)))
                    .offset(x: CGFloat(index) * (coordinator.macSide == .left ? -12 : 12))
            }
            if coordinator.files.count > 1 {
                Text("\(coordinator.files.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.signalTone, in: Capsule())
                    .offset(x: 104, y: -130)
            }
        }
        .scaleEffect(isLifted ? 1 : 0.55)
        .opacity(isLifted && draggingTransferID == nil && !isTransferring ? 1 : 0)
        .shadow(color: .black.opacity(isLifted ? 0.4 : 0), radius: 30, y: 18)
        .onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .named(canvasSpace))
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { center in
            coordinator.launchOrigin = center
        }
        .gesture(flickToSend)
    }

    private var flickToSend: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(canvasSpace))
            .onChanged { drag in
                guard !coordinator.files.isEmpty, !isTransferring else { return }
                if draggingTransferID == nil {
                    let transferID = UUID()
                    draggingTransferID = transferID
                    let leadFile = coordinator.files[0]
                    coordinator.stage.beginDrag(id: transferID, thumbnail: leadFile.thumbnail, fileName: leadFile.name, at: drag.location)
                }
                guard let draggingTransferID else { return }
                coordinator.moveDragging(id: draggingTransferID, to: drag.location)
            }
            .onEnded { drag in
                guard let transferID = draggingTransferID else { return }
                coordinator.endDragging(
                    id: transferID,
                    at: drag.location,
                    predictedEnd: drag.predictedEndLocation,
                    origin: coordinator.launchOrigin ?? drag.startLocation
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    draggingTransferID = nil
                }
            }
    }

    private var helpPanel: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: helpSymbol)
                .font(.title3)
                .foregroundStyle(helpTint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(helpTitle)
                    .font(.subheadline.weight(.semibold))
                Text(helpDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .modifier(CloseButtonGlass())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .modifier(PanelGlass(cornerRadius: 28))
    }

    private var helpTitle: String {
        switch coordinator.phase {
        case .noTrustedMac:
            return "No Mac paired yet"
        case .failed:
            return "Couldn't send"
        case .ready:
            return "Ready"
        default:
            return "Looking for your Mac…"
        }
    }

    private var helpDetail: String {
        switch coordinator.phase {
        case .noTrustedMac:
            return "Open AirProDrop and pair your Mac first, then share again."
        case .failed(let message):
            return message
        case .ready:
            return "Flick the file toward your Mac to send it."
        default:
            return "Keep Wi-Fi on and AirProDrop running on your Mac."
        }
    }

    private var helpSymbol: String {
        switch coordinator.phase {
        case .noTrustedMac, .failed:
            return "exclamationmark.circle"
        case .ready:
            return "laptopcomputer"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }

    private var helpTint: Color {
        if case .failed = coordinator.phase {
            return .red
        }
        return .signalTone
    }

    private func dismiss() {
        guard !isTransferring else { return }
        coordinator.cancel()
    }
}
