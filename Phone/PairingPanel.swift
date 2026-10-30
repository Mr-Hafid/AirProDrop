import SwiftUI

struct PairingPanel: View {
    let candidates: [DiscoveredMac]
    let step: PhoneCoordinator.PairingStep
    let errorMessage: String?
    let onSelectMac: (DiscoveredMac) -> Void
    let onSubmitCode: (String) -> Void
    let onCancel: () -> Void
    let onClose: () -> Void

    private var isVerifyingCode: Bool {
        if case .verifyingCode = step { return true }
        return false
    }

    var body: some View {
        Group {
            switch step {
            case .choosingMac:
                searchContent(requestingMacID: nil)
            case .requestingCode(let mac):
                searchContent(requestingMacID: mac.id)
            case .enteringCode(let mac), .verifyingCode(let mac):
                PairingCodeEntry(mac: mac, isVerifying: isVerifyingCode, errorMessage: errorMessage, onSubmit: onSubmitCode, onCancel: onCancel)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .modifier(PanelGlass())
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .modifier(CloseButtonGlass())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private func searchContent(requestingMacID: String?) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(candidates.isEmpty ? "Looking for Macs…" : "Tap your Mac")
                    .font(.headline)
                Text(candidates.isEmpty
                     ? "Open AirProDrop on your Mac and keep Wi-Fi turned on."
                     : "A pairing code will appear on your Mac's screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SignalRadar(candidates: candidates, requestingMacID: requestingMacID, onSelect: onSelectMac)
                .frame(height: 340)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct SignalRadar: View {
    let candidates: [DiscoveredMac]
    let requestingMacID: String?
    let onSelect: (DiscoveredMac) -> Void

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let beaconPositions = RadarLayout.positions(for: candidates.map(\.id), in: proxy.size)
            ZStack {
                ForEach(1...3, id: \.self) { ringIndex in
                    Circle()
                        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                        .frame(width: radius * 2 * CGFloat(ringIndex) / 3, height: radius * 2 * CGFloat(ringIndex) / 3)
                        .position(center)
                }

                SignalPulse()

                Image(systemName: "iphone")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.signalTone)
                    .shadow(color: .signalTone.opacity(0.8), radius: 10)
                    .position(center)

                ForEach(candidates) { mac in
                    let isRequesting = mac.id == requestingMacID
                    Button {
                        onSelect(mac)
                    } label: {
                        MacBeacon(name: mac.name, isRequesting: isRequesting)
                    }
                    .buttonStyle(.plain)
                    .disabled(requestingMacID != nil)
                    .opacity(requestingMacID == nil || isRequesting ? 1 : 0.35)
                    .position(beaconPositions[mac.id] ?? center)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.7), value: candidates.map(\.id))
    }
}

private enum RadarLayout {
    private static let beaconFootprint = CGSize(width: 130, height: 86)
    private static let centerClearance: CGFloat = 36
    private static let spacing: CGFloat = 10
    private static let innerRadiusFraction = 0.3
    private static let placementAttempts: UInt64 = 80

    static func positions(for macIDs: [String], in size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let halfWidth = max(size.width / 2 - beaconFootprint.width / 2, 1)
        let halfHeight = max(size.height / 2 - beaconFootprint.height / 2, 1)
        var placed: [String: CGPoint] = [:]

        for macID in macIDs.sorted() {
            var bestPoint = center
            var bestSeparation = -CGFloat.infinity
            for attempt in 0..<placementAttempts {
                let seed = stableHash(of: macID, salt: attempt)
                let angle = Double(seed & 0xFFFF) / Double(0xFFFF) * 2 * Double.pi
                let radiusFraction = innerRadiusFraction + (1 - innerRadiusFraction) * Double((seed >> 16) & 0xFFFF) / Double(0xFFFF)
                let point = CGPoint(
                    x: center.x + halfWidth * CGFloat(radiusFraction * cos(angle)),
                    y: center.y + halfHeight * CGFloat(radiusFraction * sin(angle))
                )
                let separation = separation(of: point, from: Array(placed.values), center: center)
                if separation > bestSeparation {
                    bestPoint = point
                    bestSeparation = separation
                }
                if separation >= spacing {
                    break
                }
            }
            placed[macID] = bestPoint
        }
        return placed
    }

    private static func separation(of point: CGPoint, from placedPoints: [CGPoint], center: CGPoint) -> CGFloat {
        let horizontalGapToCenter = abs(point.x - center.x) - beaconFootprint.width / 2
        let verticalGapToCenter = abs(point.y - center.y) - beaconFootprint.height / 2
        let centerSeparation = max(horizontalGapToCenter, verticalGapToCenter) - centerClearance + spacing
        let beaconSeparation = placedPoints.map { other in
            max(abs(point.x - other.x) - beaconFootprint.width, abs(point.y - other.y) - beaconFootprint.height)
        }
        return ([centerSeparation] + beaconSeparation).min() ?? centerSeparation
    }

    private static func stableHash(of text: String, salt: UInt64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325 ^ (salt &* 0x9E3779B97F4A7C15)
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        return hash
    }
}

private struct SignalPulse: View {
    private static let ringCount = 3
    private static let period: TimeInterval = 2.6

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) / 2
                let time = timeline.date.timeIntervalSinceReferenceDate
                for ringIndex in 0..<Self.ringCount {
                    let phase = (time / Self.period + Double(ringIndex) / Double(Self.ringCount)).truncatingRemainder(dividingBy: 1)
                    let radius = maxRadius * (0.1 + 0.9 * phase)
                    let ringRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    let fade = pow(1 - phase, 1.6)
                    context.fill(Circle().path(in: ringRect), with: .color(.signalTone.opacity(0.07 * fade)))
                    context.stroke(Circle().path(in: ringRect), with: .color(.signalTone.opacity(0.75 * fade)), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MacBeacon: View {
    let name: String
    let isRequesting: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Circle().strokeBorder(Color.signalTone.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: .signalTone.opacity(0.45), radius: 12)
                if isRequesting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 62, height: 62)

            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 140)
        }
        .contentShape(Rectangle())
    }
}

private struct PairingCodeEntry: View {
    let mac: DiscoveredMac
    let isVerifying: Bool
    let errorMessage: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.signalTone)
                .shadow(color: .signalTone.opacity(0.7), radius: 10)

            VStack(spacing: 6) {
                Text("Enter the code from \(mac.name)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Your Mac is showing a 6-digit code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($isCodeFieldFocused)
                .disabled(isVerifying)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue {
                        code = digits
                        return
                    }
                    guard digits.count == 6 else { return }
                    onSubmit(digits)
                }

            if isVerifying {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear { isCodeFieldFocused = true }
        .onChange(of: errorMessage) { _, newValue in
            guard newValue != nil else { return }
            code = ""
            isCodeFieldFocused = true
        }
    }
}
