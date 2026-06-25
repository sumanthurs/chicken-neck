import AppKit
import SwiftUI

/// A self-drawn floating banner near the top of the screen. Used instead of
/// relying on macOS Notification Center, which is unreliable for locally-built
/// (ad-hoc signed) apps, this needs no permission and always shows.
@MainActor
final class PopupAlert {
    static let shared = PopupAlert()

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(title: String, message: String, duration: TimeInterval = 4) {
        dismissWork?.cancel()

        let hosting = NSHostingView(rootView: BannerView(title: title, message: message))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = self.panel ?? makePanel()
        panel.setContentSize(size)
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct BannerView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Text("🐔").font(.system(size: 34))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.orange.opacity(0.55), lineWidth: 1))
    }
}
