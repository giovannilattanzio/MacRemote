import AppKit
import MacRemoteKit
import SwiftUI

/// A short on-screen note when the mode changes, so someone across the
/// room knows what the D-pad now does.
final class ModeHUD {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ mode: RemoteMode) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: ModeHUDView(mode: mode))
        panel.contentView = host
        let size = host.fittingSize
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.18,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

struct ModeHUDView: View {
    let mode: RemoteMode

    var body: some View {
        Label("\(mode.title) Mode", systemImage: mode.symbol)
            .font(.title2.weight(.semibold))
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.lg)
            .modifier(HUDBackground())
            .padding(Space.xl)
    }
}

/// Liquid Glass on macOS 26, a HUD material before it.
private struct HUDBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
