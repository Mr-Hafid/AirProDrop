import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private lazy var coordinator = ShareCoordinator(
        onFinish: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        },
        onCancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    )

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        modalPresentationStyle = .overFullScreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let hostingController = UIHostingController(rootView: ShareSendView(coordinator: coordinator))
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)

        coordinator.start(with: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clearAncestorBackgrounds()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        clearAncestorBackgrounds()
    }

    private func clearAncestorBackgrounds() {
        var ancestor = view.superview
        while let current = ancestor {
            current.backgroundColor = .clear
            ancestor = current.superview
        }
        view.window?.backgroundColor = .clear
    }
}
