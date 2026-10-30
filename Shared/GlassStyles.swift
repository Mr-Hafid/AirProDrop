#if os(iOS)
import SwiftUI

extension Color {
    static let signalTone = Color(red: 0.84, green: 0.97, blue: 0.90)
}

struct LiquidPanelTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(x: phase.isIdentity ? 1 : 0.88, y: phase.isIdentity ? 1 : 0.62, anchor: .bottom)
            .offset(y: phase.isIdentity ? 0 : 70)
            .blur(radius: phase.isIdentity ? 0 : 18)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension Transition where Self == LiquidPanelTransition {
    static var liquidPanel: LiquidPanelTransition { LiquidPanelTransition() }
}

struct PanelGlass: ViewModifier {
    var cornerRadius: CGFloat = 34

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.black.opacity(0.5)), in: shape)
        } else {
            content.background {
                shape
                    .fill(.black.opacity(0.78))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
            }
        }
    }
}

struct CloseButtonGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Circle())
        } else {
            content.background(.white.opacity(0.1), in: Circle())
        }
    }
}
#endif
