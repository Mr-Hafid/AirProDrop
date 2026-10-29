import SwiftUI
import UIKit

final class ViewSnapshotter {
    fileprivate weak var view: UIView?

    func capture() -> UIImage? {
        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }
}

struct SnapshottableContainer<Content: View>: UIViewControllerRepresentable {
    let snapshotter: ViewSnapshotter
    let content: Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .systemBackground
        snapshotter.view = hostingController.view
        return hostingController
    }

    func updateUIViewController(_ hostingController: UIHostingController<Content>, context: Context) {
        hostingController.rootView = content
        snapshotter.view = hostingController.view
    }
}
