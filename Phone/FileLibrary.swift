import CoreGraphics
import Foundation
import Observation
import UniformTypeIdentifiers

struct LibraryItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let byteCount: Int64
    let modificationDate: Date

    var id: URL { url }

    var detailText: String {
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        let time = modificationDate.formatted(date: .omitted, time: .shortened)
        return "\(size) · \(time)"
    }
}

@Observable
final class FileLibrary {
    var items: [LibraryItem] = []
    var thumbnails: [URL: CGImage] = [:]

    @ObservationIgnored let directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @ObservationIgnored private var thumbnailsInFlight: Set<URL> = []

    func reload() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        items = urls
            .compactMap { url -> LibraryItem? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
                return LibraryItem(
                    url: url,
                    name: url.lastPathComponent,
                    byteCount: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modificationDate > $1.modificationDate }
        loadMissingThumbnails()
    }

    @discardableResult
    func adoptReceivedFile(at temporaryURL: URL, named fileName: String) -> URL? {
        let destination = FileManager.default.uniqueDestination(forFileNamed: fileName, in: directory)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
        markAsRecent(destination)
        reload()
        return destination
    }

    func importCopy(of sourceURL: URL) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let destination = FileManager.default.uniqueDestination(forFileNamed: sourceURL.lastPathComponent, in: directory)
        guard (try? FileManager.default.copyItem(at: sourceURL, to: destination)) != nil else { return }
        markAsRecent(destination)
        reload()
    }

    func importData(_ data: Data, contentType: UTType?) {
        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
        let timestamp = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        let safeTimestamp = timestamp.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let destination = FileManager.default.uniqueDestination(forFileNamed: "Photo \(safeTimestamp).\(fileExtension)", in: directory)
        guard (try? data.write(to: destination)) != nil else { return }
        reload()
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: item.url)
        thumbnails[item.url] = nil
        reload()
    }

    private func markAsRecent(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func loadMissingThumbnails() {
        for item in items where thumbnails[item.url] == nil && !thumbnailsInFlight.contains(item.url) {
            thumbnailsInFlight.insert(item.url)
            Task { @MainActor in
                let image = await ThumbnailRenderer.image(for: item.url)
                self.thumbnailsInFlight.remove(item.url)
                if let image {
                    self.thumbnails[item.url] = image
                }
            }
        }
    }
}
