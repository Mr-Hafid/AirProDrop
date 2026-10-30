import Foundation

enum AirProService {
    static let bonjourType = "_airpro._tcp"
    static let pairingModeValue = "pair"
    static let pairedModeValue = "paired"
    static let modeKey = "mode"
    static let deviceIDKey = "id"
    static let maximumFrameLength = 16 * 1024 * 1024
    static let fileChunkLength = 256 * 1024
    static let handshakeTimeout: TimeInterval = 10
    static let pairingWindowDuration: TimeInterval = 120
    static let maximumFailedPairingAttempts = 3
    static let pairingRequestCooldown: TimeInterval = 30
    static let maximumRequesterNameLength = 64

    static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

enum ScreenSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    var opposite: ScreenSide {
        self == .left ? .right : .left
    }
}

enum LocalDevice {
    private static let deviceIDDefaultsKey = "airpro.localDeviceID"

    static var identifier: String {
        if let existing = SharedContainer.string(forKey: deviceIDDefaultsKey) {
            return existing
        }
        let created = UUID().uuidString
        SharedContainer.defaults.set(created, forKey: deviceIDDefaultsKey)
        return created
    }
}

extension FileManager {
    func uniqueDestination(forFileNamed proposedName: String, in directory: URL) -> URL {
        let safeName = URL(fileURLWithPath: proposedName).lastPathComponent
        let fallbackName = safeName.isEmpty || safeName == "/" ? "File" : safeName
        let baseName = (fallbackName as NSString).deletingPathExtension
        let pathExtension = (fallbackName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fallbackName)
        var suffix = 2
        while fileExists(atPath: candidate.path) {
            let numberedName = pathExtension.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(pathExtension)"
            candidate = directory.appendingPathComponent(numberedName)
            suffix += 1
        }
        return candidate
    }
}
