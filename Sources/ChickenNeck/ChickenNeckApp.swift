import SwiftUI

@main
struct ChickenNeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let state = AppState.shared

    var body: some Scene {
        // Dashboard window. The menu-bar chicken is an AppKit NSStatusItem
        // managed in AppDelegate (SwiftUI's MenuBarExtra loops on macOS 26).
        Window("Chicken Neck", id: "dashboard") {
            ScrollView {
                MenuContentView(state: state)
            }
            .frame(width: 320, height: 640)
        }
        .windowResizability(.contentSize)
    }
}
