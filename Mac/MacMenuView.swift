import AppKit
import SwiftUI

struct MacMenuView: View {
    @Bindable var coordinator: MacCoordinator

    private var statusTitle: String {
        if let connectedPhoneName = coordinator.connectedPhoneName {
            return connectedPhoneName
        }
        if coordinator.trustedDevices.isEmpty {
            return "No iPhone paired"
        }
        return "No iPhone connected"
    }

    private var statusDetail: String {
        if coordinator.connectedPhoneName != nil {
            return "Nearby"
        }
        if coordinator.pairingCode != nil {
            return "Open AirProDrop on your iPhone, choose this Mac and enter the code"
        }
        return "Open AirProDrop on your iPhone to connect"
    }

    private var formattedPairingCode: String? {
        guard let code = coordinator.pairingCode, code.count == 6 else { return coordinator.pairingCode }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: coordinator.connectedPhoneName == nil ? "iphone" : "iphone.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(coordinator.connectedPhoneName == nil ? Color.secondary : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let formattedPairingCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairing code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedPairingCode)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    if let pairingExpiresAt = coordinator.pairingExpiresAt {
                        Text("Expires \(pairingExpiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !coordinator.trustedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trusted iPhones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(coordinator.trustedDevices) { device in
                        HStack {
                            Text(device.name)
                                .lineLimit(1)
                            Spacer()
                            Button("Forget") {
                                coordinator.forget(device)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("iPhone sits on the")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("iPhone sits on the", selection: $coordinator.phoneSide) {
                    ForEach(ScreenSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Drag a file to the \(coordinator.phoneSide.title.lowercased()) edge of the screen to send it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("Send Files…", action: coordinator.chooseFilesToSend)
                Button("Open Received Folder", action: coordinator.openReceivedFolder)
                if coordinator.pairingCode == nil {
                    Button("Pair New iPhone…", action: coordinator.openPairingWindow)
                } else {
                    Button("Cancel Pairing", action: coordinator.closePairingWindow)
                }
                Divider()
                Button("Quit AirProDrop") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 290)
    }
}
