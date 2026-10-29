import AppKit

final class EdgeDropView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.01).cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsFileURLs(sender) else { return [] }
        onHoverChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsFileURLs(sender) else { return [] }
        onHoverChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func containsFileURLs(_ draggingInfo: NSDraggingInfo) -> Bool {
        draggingInfo.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLReadingOptions)
    }

    private func fileURLs(in draggingInfo: NSDraggingInfo) -> [URL] {
        draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: fileURLReadingOptions) as? [URL] ?? []
    }

    private var fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true]
    }
}
