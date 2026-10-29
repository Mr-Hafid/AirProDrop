import PhotosUI
import QuickLook
import SwiftUI

struct ContentView: View {
    @Bindable var coordinator: PhoneCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewURL: URL?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isImportingFiles = false
    @State private var rippleSnapshot: UIImage?
    @State private var snapshotter = ViewSnapshotter()

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        ZStack {
            SnapshottableContainer(snapshotter: snapshotter, content: libraryNavigation)
                .ignoresSafeArea()
                .overlay {
                    if let rippleSnapshot {
                        Image(uiImage: rippleSnapshot)
                            .resizable()
                            .ignoresSafeArea()
                            .airDropRipple(
                                side: coordinator.macSide,
                                verticalPosition: coordinator.stage.glowVerticalPosition,
                                waveStartDate: coordinator.stage.waveStartDate
                            )
                            .allowsHitTesting(false)
                    }
                }
                .blur(radius: 6 * coordinator.stage.glowIntensity)
                .overlay {
                    Color.black
                        .opacity((colorScheme == .light ? 0.42 : 0.3) * coordinator.stage.glowIntensity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

            EdgeGlow(
                intensity: coordinator.stage.glowIntensity,
                side: coordinator.macSide,
                verticalPosition: coordinator.stage.glowVerticalPosition,
                waveStartDate: coordinator.stage.waveStartDate
            )

            FlyingCardLayer(cards: coordinator.stage.cards)

            if coordinator.showsPairingScreen {
                VStack {
                    Spacer()
                    PairingPanel(
                        candidates: coordinator.pairingCandidates,
                        step: coordinator.pairingStep,
                        errorMessage: coordinator.pairingErrorMessage,
                        onSelectMac: coordinator.requestPairingCode(from:),
                        onSubmitCode: coordinator.submitPairingCode,
                        onCancel: coordinator.cancelPairing,
                        onClose: coordinator.closePairingScreen
                    )
                    .padding(.bottom, 40)
                }
                .transition(.liquidPanel)
            }
        }
        .ignoresSafeArea(.container)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: coordinator.linkState)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: coordinator.showsPairingScreen)
        .onChange(of: coordinator.stage.waveStartDate) { _, waveStartDate in
            guard let waveStartDate else { return }
            rippleSnapshot = snapshotter.capture()
            DispatchQueue.main.asyncAfter(deadline: .now() + AirDropWave.duration) {
                guard coordinator.stage.waveStartDate == waveStartDate else { return }
                rippleSnapshot = nil
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            coordinator.stage.canvasSize = size
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                coordinator.activate()
            case .background:
                coordinator.deactivate()
            default:
                break
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            importPhotos(items)
        }
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            urls.forEach(coordinator.library.importCopy(of:))
        }
        .quickLookPreview($previewURL)
    }

    private var libraryNavigation: some View {
        NavigationStack {
            libraryContent
                .navigationTitle("AirProDrop")
                .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if coordinator.library.items.isEmpty {
            ContentUnavailableView {
                Label("No files yet", systemImage: "square.and.arrow.down.on.square")
            } description: {
                Text("Drag a file to the edge of your Mac's screen, or add photos with the button above. Touch and hold a file, then flick it toward your Mac to send it.")
            } actions: {
                Button {
                    coordinator.showNearbyMacs()
                } label: {
                    Label("Nearby Macs", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .opacity(coordinator.showsPairingScreen ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: coordinator.showsPairingScreen)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(coordinator.library.items) { item in
                        fileTile(for: item)
                    }
                }
                .padding(16)
            }
        }
    }

    private func fileTile(for item: LibraryItem) -> some View {
        FileTile(
            item: item,
            thumbnail: coordinator.library.thumbnails[item.url],
            isLifted: coordinator.draggingItemURL == item.url,
            onDelete: { coordinator.library.delete(item) }
        )
        .onTapGesture {
            previewURL = item.url
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    guard case .second(true, let drag?) = value else { return }
                    if coordinator.draggingItemURL != item.url {
                        coordinator.beginDragging(item, at: drag.startLocation)
                    }
                    coordinator.moveDragging(to: drag.location)
                }
                .onEnded { value in
                    guard case .second(true, let drag?) = value else {
                        coordinator.cancelDragging()
                        return
                    }
                    coordinator.endDragging(item, at: drag.location, predictedEnd: drag.predictedEndLocation, origin: drag.startLocation)
                }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LinkStatusBadge(linkState: coordinator.linkState, macName: coordinator.connectedMacName)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                Image(systemName: "photo.badge.plus")
            }
            Menu {
                Button {
                    isImportingFiles = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                Picker("Mac sits on the", selection: $coordinator.macSide) {
                    ForEach(ScreenSide.allCases) { side in
                        Text("Mac on the \(side.title.lowercased())").tag(side)
                    }
                }
                if !coordinator.trustedMacs.isEmpty {
                    Section("Trusted Macs") {
                        ForEach(coordinator.trustedMacs) { mac in
                            Button(role: .destructive) {
                                coordinator.forget(mac)
                            } label: {
                                Label("Forget \(mac.name)", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        selectedPhotos = []
        for item in items {
            Task { @MainActor in
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                coordinator.library.importData(data, contentType: item.supportedContentTypes.first)
            }
        }
    }
}

private struct FileTile: View {
    let item: LibraryItem
    let thumbnail: CGImage?
    let isLifted: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(.secondarySystemBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .overlay {
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Menu {
                    ShareLink(item: item.url)
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(6)
                }
            }

            Text(item.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(item.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(isLifted ? 0.25 : 1)
        .contentShape(Rectangle())
    }
}

private struct LinkStatusBadge: View {
    let linkState: PhoneCoordinator.LinkState
    let macName: String?

    private var title: String {
        switch linkState {
        case .connected:
            return macName ?? "Mac"
        case .connecting:
            return "Connecting…"
        case .needsPairing:
            return "Not paired"
        case .searching:
            return "Looking for Mac…"
        }
    }

    private var dotColor: Color {
        switch linkState {
        case .connected: return .green
        case .connecting: return .orange
        case .needsPairing, .searching: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
    }
}
