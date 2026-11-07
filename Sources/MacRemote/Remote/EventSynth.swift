import AppKit
import CoreGraphics
import MacRemoteKit

/// Where the engine sends what a button does. EventSynth posts real events;
/// the self-test records them instead.
protocol EffectSink: AnyObject {
    /// The button went down.
    func begin(_ action: RemoteAction)
    /// The button came up (mouse buttons are released here).
    func end(_ action: RemoteAction)
    func movePointer(dx: Double, dy: Double)
    func scroll(dx: Double, dy: Double)
}

/// The on-screen keyboard as the engine sees it: a sink for the actions in
/// KeyboardButtons while it is open.
protocol KeyboardInput: EffectSink {
    var isOpen: Bool { get }
    func open()
}

/// Posts keyboard, media, and mouse events to the Mac. Needs Accessibility.
final class EventSynth: EffectSink {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var leftDown = false
    private var clicks = ClickCounter()
    private var clickCount = 1

    func begin(_ action: RemoteAction) {
        switch action.effect {
        case .key(let code, let modifiers): key(code, modifiers)
        case .media(let key): media(key)
        case .leftClick:
            clickCount = clicks.click(at: ProcessInfo.processInfo.systemUptime)
            mouse(.leftMouseDown, button: .left)
            leftDown = true
        case .rightClick: mouse(.rightMouseDown, button: .right)
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        case .sleepDisplay:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        case .none, .move, .scroll, .toggleMode, .keyboard: break
        }
    }

    func end(_ action: RemoteAction) {
        switch action.effect {
        case .leftClick:
            mouse(.leftMouseUp, button: .left)
            leftDown = false
        case .rightClick: mouse(.rightMouseUp, button: .right)
        default: break
        }
    }

    func movePointer(dx: Double, dy: Double) {
        guard let current = CGEvent(source: nil)?.location else { return }
        let target = clamp(CGPoint(x: current.x + dx, y: current.y + dy), from: current)
        let type: CGEventType = leftDown ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func scroll(dx: Double, dy: Double) {
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    // MARK: Events

    private static let modifierKeys: [(KeyModifiers, CGKeyCode, CGEventFlags)] = [
        (.command, 55, .maskCommand), (.shift, 56, .maskShift),
        (.option, 58, .maskAlternate), (.control, 59, .maskControl),
    ]

    /// Presses the modifiers as real keys around the key, so shortcuts like
    /// Command-Tab that watch the modifier itself work too.
    private func key(_ code: UInt16, _ modifiers: KeyModifiers) {
        let used = Self.modifierKeys.filter { modifiers.contains($0.0) }
        var flags: CGEventFlags = []
        for (_, keyCode, flag) in used {
            flags.insert(flag)
            post(keyCode, down: true, flags: flags)
        }
        post(CGKeyCode(code), down: true, flags: flags)
        post(CGKeyCode(code), down: false, flags: flags)
        for (_, keyCode, flag) in used.reversed() {
            flags.remove(flag)
            post(keyCode, down: false, flags: flags)
        }
    }

    /// Types text into the app in front, whatever the keyboard layout.
    func type(_ text: String) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            let units = Array(text.utf16)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event?.setIntegerValueField(.eventSourceUserData, value: RemoteKeyFilter.marker)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Presses one key with no modifiers.
    func press(_ code: UInt16) { key(code, []) }

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        // RemoteKeyFilter lets MacRemote's own keys through.
        event?.setIntegerValueField(.eventSourceUserData, value: RemoteKeyFilter.marker)
        event?.post(tap: .cghidEventTap)
    }

    /// Media keys are "system defined" events, subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    private func media(_ key: MediaKey) {
        for down in [true, false] {
            let state = down ? 0xA00 : 0xB00
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int(key.rawValue) << 16 | state, data2: -1
            )?.cgEvent
            // RemoteKeyFilter lets MacRemote's own media keys through.
            event?.setIntegerValueField(.eventSourceUserData, value: RemoteKeyFilter.marker)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func mouse(_ type: CGEventType, button: CGMouseButton) {
        guard let location = CGEvent(source: nil)?.location,
              let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(button == .left ? clickCount : 1))
        event.post(tap: .cghidEventTap)
    }

    /// Keeps the pointer on a screen: free to cross into a neighboring
    /// display, stopped at the outer edges.
    private func clamp(_ point: CGPoint, from current: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let bounds = ids.map(CGDisplayBounds)
        if bounds.contains(where: { $0.contains(point) }) { return point }
        guard let screen = bounds.first(where: { $0.contains(current) }) ?? bounds.first else { return point }
        return CGPoint(x: min(max(point.x, screen.minX), screen.maxX - 1),
                       y: min(max(point.y, screen.minY), screen.maxY - 1))
    }
}
