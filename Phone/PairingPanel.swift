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
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("Pair with your Mac")
                .font(.headline)

            if candidates.count > 1 {
                Picker("Mac", selection: Binding(get: { selectedMac?.id ?? "" }, set: { selectedMacID = $0 })) {
                    ForEach(candidates) { mac in
                        Text(mac.name).tag(mac.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Text("Enter the 6-digit code shown in the AirPro Drop menu on \(selectedMac?.name ?? "your Mac").")
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
                    guard digits.count == 6, let selectedMac else { return }
                    onSubmit(digits, selectedMac)
                }

            if isInProgress {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .onAppear { isCodeFieldFocused = true }
        .onChange(of: errorMessage) { _, newValue in
            guard newValue != nil else { return }
            code = ""
            isCodeFieldFocused = true
        }
    }
}
