import SwiftUI

@main
struct AirProPhoneApp: App {
    @State private var coordinator = PhoneCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: coordinator)
        }
    }
}
