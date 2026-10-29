import SwiftUI

enum AirDropWave {
    static let duration: TimeInterval = 1.3

    static func elapsed(since startDate: Date?, at date: Date) -> Double {
        guard let startDate else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        return elapsed >= duration ? 0 : max(elapsed, 0)
    }

    static func isRunning(since startDate: Date?) -> Bool {
        guard let startDate else { return false }
        return Date().timeIntervalSince(startDate) < duration
    }

    static func origin(in size: CGSize, side: ScreenSide, verticalPosition: Double) -> CGPoint {
        CGPoint(
            x: side == .left ? 0 : size.width,
            y: size.height * min(max(verticalPosition, 0.1), 0.9)
        )
    }
}

struct EdgeGlow: View, Animatable {
    var intensity: Double
    var side: ScreenSide
    var verticalPosition: Double
    var waveStartDate: Date?

    @State private var clockOrigin = Date()

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(intensity, verticalPosition) }
        set {
            intensity = newValue.first
            verticalPosition = newValue.second
        }
    }

    private var isIdle: Bool {
        intensity < 0.001 && !AirDropWave.isRunning(since: waveStartDate)
    }

    var body: some View {
        TimelineView(.animation(paused: isIdle)) { timeline in
            GeometryReader { proxy in
                let size = proxy.size
                let origin = AirDropWave.origin(in: size, side: side, verticalPosition: verticalPosition)
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.airDropGlow(
                            .float2(size.width, size.height),
                            .float2(origin.x, origin.y),
                            .float(timeline.date.timeIntervalSince(clockOrigin)),
                            .float(intensity),
                            .float(AirDropWave.elapsed(since: waveStartDate, at: timeline.date)),
                            .float(side == .left ? 1 : -1)
                        )
                    )
            }
        }
        .opacity(isIdle ? 0 : 1)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct ContentRippleModifier: ViewModifier {
    var side: ScreenSide
    var verticalPosition: Double
    var waveStartDate: Date?
    var amplitude: Double = 14

    func body(content: Content) -> some View {
        let isRunning = AirDropWave.isRunning(since: waveStartDate)
        TimelineView(.animation(paused: !isRunning)) { timeline in
            content.visualEffect { effectContent, proxy in
                let origin = AirDropWave.origin(in: proxy.size, side: side, verticalPosition: verticalPosition)
                return effectContent.layerEffect(
                    ShaderLibrary.contentRipple(
                        .float2(origin.x, origin.y),
                        .float2(proxy.size.width, proxy.size.height),
                        .float(AirDropWave.elapsed(since: waveStartDate, at: timeline.date)),
                        .float(amplitude),
                        .float(side == .left ? 1 : -1)
                    ),
                    maxSampleOffset: CGSize(width: amplitude * 1.3, height: amplitude * 1.3),
                    isEnabled: isRunning
                )
            }
        }
    }
}

extension View {
    func airDropRipple(side: ScreenSide, verticalPosition: Double, waveStartDate: Date?) -> some View {
        modifier(ContentRippleModifier(side: side, verticalPosition: verticalPosition, waveStartDate: waveStartDate))
    }
}
