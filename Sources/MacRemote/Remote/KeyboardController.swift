import AppKit
import ApplicationServices
import Combine
import os
import MacRemoteKit
import SwiftUI

/// The on-screen keyboard: a floating panel the remote types on. It opens by
/// itself when the remote selects a text field (KeyboardTrigger decides), or
/// from the Show Keyboard action and menu item. The app in front keeps focus;
/// the keyboard posts the typed text to it.
final class KeyboardController: ObservableObject, KeyboardInput {
    static let settingKey = "keyboardForTextFields"

    @Published private(set) var keyboard = OnScreenKeyboard()
    @Published private(set) var isOpen = false

    /// Where typed text goes. EventSynth posts it; the self-test records it.
    var output: (OnScreenKeyboard.Output) -> Void
    /// The focused element, and whether it takes text. Replaced by the self-test.
    var focus: () -> (element: AXUIElement?, isText: Bool) = KeyboardController.systemFocus
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// False in the self-test: no panel on screen.
    var showsPanel = true

    private let defaults: UserDefaults
    private var trigger = KeyboardTrigger<AXUIElement>()
    /// True when a text field opened it, so focus leaving closes it.
    private var openedByFocus = false
    private var closedAt: TimeInterval = -.infinity
    private var poll: Timer?
    private var panel: NSPanel?
    private let log = Logger(subsystem: "com.gilattanzio.macremote", category: "keyboard")

    init(defaults: UserDefaults, output: @escaping (OnScreenKeyboard.Output) -> Void) {
        self.defaults = defaults
        self.output = output
    }

    var opensForTextFields: Bool { defaults.object(forKey: Self.settingKey) as? Bool ?? true }

    /// True while open and a moment after, so the key that closed it
    /// (macOS's copy of Back from a shared remote) is dropped too.
    var holdsRemoteKeys: Bool { isOpen || clock() - closedAt < KeyGuard.window }

    // MARK: Opening

    func open() { open(byFocus: false) }

    private func open(byFocus: Bool) {
        guard !isOpen else { return }
        openedByFocus = byFocus
        keyboard.reset()
        isOpen = true
        log.info("open, by focus: \(byFocus)")
        if showsPanel { showPanel() }
        if byFocus { startPolling() }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        openedByFocus = false
        closedAt = clock()
        trigger.closed()
        log.info("closed")
        panel?.orderOut(nil)
    }

    func toggle() { isOpen ? close() : open() }

    // MARK: Watching focus

    /// Called for every remote press while the keyboard is shut.
    func remotePressed(_ action: RemoteAction) {
        guard opensForTextFields, !isOpen else { return }
        trigger.remotePressed(click: action == .leftClick, at: clock()) { focus().element }
        startPolling()
    }

    /// Reads the focused element. The timer calls it; the self-test calls it directly.
    func check() {
        let now = clock()
        let current = focus()
        switch trigger.observe(focus: current.element, isText: current.isText,
                               showing: isOpen && openedByFocus, at: now) {
        case .show: open(byFocus: true)
        case .hide: close()
        case .none: break
        }
        if !(isOpen && openedByFocus) && !trigger.isWatching(at: now) { stopPolling() }
    }

    private func startPolling() {
        guard poll == nil, showsPanel else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.keyboard.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    nonisolated(unsafe) private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // A hung app must not freeze the remote.
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    nonisolated static func systemFocus() -> (element: AXUIElement?, isText: Bool) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, false) }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let isText = TextInput.accepts(role: string(element, kAXRoleAttribute),
                                       subrole: string(element, kAXSubroleAttribute),
                                       editable: settable.boolValue)
        return (element, isText)
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: Remote buttons (KeyboardInput)

    func begin(_ action: RemoteAction) {
        switch action {
        case .arrowUp: keyboard.move(.up)
        case .arrowDown: keyboard.move(.down)
        case .arrowLeft: keyboard.move(.left)
        case .arrowRight: keyboard.move(.right)
        case .returnKey: pressFocused()
        case .escape: close()
        case .delete: output(.delete)
        case .space: output(.text(" "))
        default: break
        }
    }

    func end(_ action: RemoteAction) {}
    func movePointer(dx: Double, dy: Double) {}
    func scroll(dx: Double, dy: Double) {}

    private func pressFocused() {
        guard let typed = keyboard.press() else { return }
        if typed == .hide { close() } else { output(typed) }
    }

    /// A click on a key, with the Mac's own pointer.
    func tap(row: Int, column: Int) {
        while keyboard.row != row { keyboard.move(.down) }
        while keyboard.column != column { keyboard.move(.right) }
        pressFocused()
    }

    // MARK: Panel

    /// For snapshots.
    var panelWindow: NSWindow? { panel }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = panel.contentView?.fittingSize ?? .zero
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + Space.section,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = FirstClickHostingView(rootView: KeyboardView(controller: self))
        return panel
    }
}

/// Never takes focus from the app being typed into.
private final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Keys respond to the first click, though the panel is never active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
