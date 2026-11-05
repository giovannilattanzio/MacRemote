import Foundation

/// Decides which keyboard events to drop when "Only MacRemote responds to
/// the remote" is on. The hidutil key block (KeyBlock) does that on macOS 26,
/// but macOS 12 still turns the remote's D-pad into arrow keys, so in Pointer
/// mode Finder scrolls while the pointer moves.
///
/// The app tells the guard about every keyboard-page button the remote
/// presses and releases, and asks it about every key event MacRemote did not
/// post. An event is the remote's when its key matches a remote button that is
/// held, or was pressed or released a moment ago. Keys never wait: the Mac's
/// own keyboard is never delayed.
public struct KeyGuard: Sendable {
    /// How far apart the remote's report and macOS's key event can be.
    public static let window: TimeInterval = 0.3

    private var held: Set<UInt16> = []
    private var last: [UInt16: TimeInterval] = [:]

    public init() {}

    /// The remote's button went down or up.
    public mutating func remote(_ usage: HIDUsage, pressed: Bool, at time: TimeInterval) {
        guard let code = Self.keyCode(for: usage) else { return }
        if pressed { held.insert(code) } else { held.remove(code) }
        last[code] = time
    }

    /// True when the key event (a macOS virtual key code) came from the remote.
    public func cameFromRemote(_ keyCode: UInt16, at time: TimeInterval) -> Bool {
        if held.contains(keyCode) { return true }
        guard let seen = last[keyCode] else { return false }
        return abs(time - seen) <= Self.window
    }

    /// The macOS virtual key code macOS makes from a remote's keyboard usage.
    public static func keyCode(for usage: HIDUsage) -> UInt16? {
        guard usage.page == HIDUsage.keyboardPage else { return nil }
        return codes[usage.usage]
    }

    /// Keyboard usages Fire TV remotes send, to kVK_* codes.
    private static let codes: [UInt32: UInt16] = [
        0x52: 126, 0x51: 125, 0x50: 123, 0x4F: 124, // arrows
        0x28: 36, 0x58: 76,                         // Return, keypad Enter
        0x29: 53, 0x2C: 49, 0x2B: 48, 0x2A: 51,     // Escape, Space, Tab, Delete
        0x4A: 115, 0x4D: 119, 0x4B: 116, 0x4E: 121, // Home, End, Page Up, Page Down
        0x65: 110,                                  // Application (menu) key
    ]
}
