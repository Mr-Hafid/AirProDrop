import AppKit
import SwiftUI

@main
struct AirProMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(coordinator: appDelegate.coordinator)
        } label: {
            Image(systemName: appDelegate.coordinator.connectedPhoneName == nil ? "iphone" : "iphone.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = MacCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }
}
