import SwiftUI

struct PairingPanel: View {
    let candidates: [DiscoveredMac]
    let isInProgress: Bool
    let errorMessage: String?
    let onSubmit: (String, DiscoveredMac) -> Void

    @State private var code = ""
    @State private var selectedMacID: String?
    @FocusState private var isCodeFieldFocused: Bool

    private var selectedMac: DiscoveredMac? {
        candidates.first { $0.id == selectedMacID } ?? candidates.first
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Nearby Macs")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(candidates) { mac in
                    nearbyMacRow(mac)
                }
            }

            if let selectedMac {
                if selectedMac.isAcceptingPairing {
                    Text("Enter the code shown in the AirProDrop menu on \(selectedMac.name).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .focused($isCodeFieldFocused)
                        .disabled(isInProgress)
                        .onChange(of: code) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(6))
                            if digits != newValue {
                                code = digits
                                return
                            }
                            guard digits.count == 6 else { return }
                            onSubmit(digits, selectedMac)
                        }
                } else {
                    Text("On \(selectedMac.name), open the AirProDrop menu and click Pair New iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if isInProgress {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .onAppear { isCodeFieldFocused = true }
        .onChange(of: selectedMac?.isAcceptingPairing) { _, isAccepting in
            guard isAccepting == true else { return }
            isCodeFieldFocused = true
        }
        .onChange(of: errorMessage) { _, newValue in
            guard newValue != nil else { return }
            code = ""
            isCodeFieldFocused = true
        }
    }

    private func nearbyMacRow(_ mac: DiscoveredMac) -> some View {
        Button {
            selectedMacID = mac.id
            code = ""
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title3)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mac.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(mac.isAcceptingPairing ? "Ready to pair" : "Not pairing yet")
                        .font(.caption)
                        .foregroundStyle(mac.isAcceptingPairing ? Color.green : Color.secondary)
                }
                Spacer()
                if mac.id == selectedMac?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
