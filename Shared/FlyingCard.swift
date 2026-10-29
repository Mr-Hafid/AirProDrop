import SwiftUI

struct FlyingCard: Identifiable, Equatable {
    let id: UUID
    var thumbnail: CGImage?
    var fileName: String
    var position: CGPoint
    var scale: CGFloat
    var opacity: Double
    var rotation: Double = 0
    var progress: Double?
}

struct ThumbnailCard: View {
    let thumbnail: CGImage?
    let fileName: String
    var progress: Double?
    var width: CGFloat = 190

    private var height: CGFloat {
        guard let thumbnail, thumbnail.width > 0 else { return width * 0.75 }
        let aspectRatio = CGFloat(thumbnail.height) / CGFloat(thumbnail.width)
        return width * min(max(aspectRatio, 0.6), 1.4)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(width: width, height: height)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 34))
                            Text(fileName)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }
                        .foregroundStyle(.secondary)
                    }
            }

            if let progress, progress < 1 {
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(10)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }
}

struct FlyingCardLayer: View {
    let cards: [FlyingCard]

    var body: some View {
        ZStack {
            ForEach(cards) { card in
                ThumbnailCard(thumbnail: card.thumbnail, fileName: card.fileName, progress: card.progress)
                    .scaleEffect(card.scale)
                    .rotationEffect(.degrees(card.rotation))
                    .opacity(card.opacity)
                    .position(card.position)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
