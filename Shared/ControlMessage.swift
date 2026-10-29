import Foundation

struct TransferAnnouncement: Codable, Equatable {
    let id: UUID
    let fileName: String
    let byteCount: Int64
    let thumbnailData: Data?
    let verticalPosition: Double
}

enum ControlMessage: Codable, Equatable {
    case edgeHover(intensity: Double, verticalPosition: Double)
    case transferStart(TransferAnnouncement)
    case transferFailed(id: UUID)
}
