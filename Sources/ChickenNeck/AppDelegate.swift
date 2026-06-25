import AppKit
import SwiftUI
import Combine
import UserNotifications

/// Owns the menu-bar chicken as a plain AppKit `NSStatusItem` + `NSPopover`.
///
/// We deliberately do NOT use SwiftUI's `MenuBarExtra`: a Window scene plus a
/// MenuBarExtra whose label reads observable state (or uses `isInserted:`) sends
/// SwiftUI's menu rebuild into an infinite 100%-CPU loop on macOS 26. Driving
/// the status item imperatively here sidesteps that entirely, and lets the
/// chicken change colour with your posture for free.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState.shared
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show notification banners even while Chicken Neck is the active app
        // (macOS suppresses them by default for the foreground app).
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ChickenIcon.menuBar(color: state.menuBarNSColor)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.isVisible = state.showMenuBarIcon
        statusItem = item

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ScrollView { MenuContentView(state: state) }.frame(width: 300, height: 560))

        // Recolour the chicken when posture severity changes.
        state.$severity
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusItem?.button?.image = ChickenIcon.menuBar(color: self?.state.menuBarNSColor ?? .secondaryLabelColor)
            }
            .store(in: &cancellables)

        // Show / hide from the Settings toggle.
        state.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

extension PostureSeverity: Equatable {}
