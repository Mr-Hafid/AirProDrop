import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum ThumbnailRenderer {
    static func image(for url: URL, maximumPixelSize: CGFloat = 480) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maximumPixelSize, height: maximumPixelSize),
            scale: 1,
            representationTypes: .all
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    static func encodedData(from image: CGImage) -> Data? {
        let hasTransparency: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            hasTransparency = false
        default:
            hasTransparency = true
        }
        let type = hasTransparency ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func image(from data: Data?) -> CGImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
