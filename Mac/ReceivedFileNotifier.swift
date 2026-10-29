import AppKit
import UniformTypeIdentifiers
import UserNotifications

final class ReceivedFileNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let fileURLKey = "fileURL"
    private let categoryIdentifier = "receivedFile"
    private let showInFinderActionIdentifier = "showInFinder"

    func start() {
        center.delegate = self
        let showInFinderAction = UNNotificationAction(identifier: showInFinderActionIdentifier, title: "Show in Finder")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryIdentifier, actions: [showInFinderAction], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyReceived(fileAt url: URL, from senderName: String, thumbnailData: Data?) {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = "Sent “\(url.lastPathComponent)” to Downloads"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [fileURLKey: url.path]
        if let attachment = makeThumbnailAttachment(from: thumbnailData) {
            content.attachments = [attachment]
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static func isMedia(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let path = response.notification.request.content.userInfo[fileURLKey] as? String else { return }
        let fileURL = URL(fileURLWithPath: path)
        switch response.actionIdentifier {
        case showInFinderActionIdentifier:
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        case UNNotificationDefaultActionIdentifier:
            NSWorkspace.shared.open(fileURL)
        default:
            break
        }
    }

    private func makeThumbnailAttachment(from data: Data?) -> UNNotificationAttachment? {
        guard let data else { return nil }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let attachmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airpro-drop-thumbnail-\(UUID().uuidString)")
            .appendingPathExtension(isPNG ? "png" : "jpg")
        guard (try? data.write(to: attachmentURL)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "thumbnail", url: attachmentURL)
    }
}
