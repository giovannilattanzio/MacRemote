import Foundation

/// Modifier keys for a synthesized key press.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// Media and system keys, by their NX_KEYTYPE number (IOKit hidsystem/ev_keymap.h).
public enum MediaKey: Int32, Sendable {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3
    case mute = 7, play = 16, next = 17, previous = 18
}

/// What an action does on the Mac. The app turns each into CGEvents.
public enum Effect: Equatable, Sendable {
    case none
    /// macOS virtual key code (kVK_*) plus modifiers.
    case key(UInt16, KeyModifiers)
    case media(MediaKey)
    /// A direction of pointer movement while the button is held.
    case move(dx: Double, dy: Double)
    case leftClick, rightClick
    /// A direction of scrolling while the button is held.
    case scroll(dx: Double, dy: Double)
    case missionControl, sleepDisplay
    case toggleMode
}

/// Everything a remote button can be set to.
public enum RemoteAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    // Keys
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case returnKey, escape, space, tab, delete, pageUp, pageDown
    case switchApp, nextWindow, closeWindow, fullScreen, spotlight
    // Pointer
    case pointerUp, pointerDown, pointerLeft, pointerRight
    case leftClick, rightClick, scrollUp, scrollDown, scrollLeft, scrollRight
    // Media
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    // System
    case missionControl, sleepDisplay, toggleMode

    public var id: String { rawValue }

    public enum Group: String, CaseIterable, Sendable {
        case keys = "Keys", pointer = "Pointer", media = "Media", system = "System"
    }

    public var group: Group {
        switch self {
        case .none, .missionControl, .sleepDisplay, .toggleMode: .system
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .returnKey, .escape, .space, .tab,
             .delete, .pageUp, .pageDown, .switchApp, .nextWindow, .closeWindow, .fullScreen, .spotlight: .keys
        case .pointerUp, .pointerDown, .pointerLeft, .pointerRight, .leftClick, .rightClick,
             .scrollUp, .scrollDown, .scrollLeft, .scrollRight: .pointer
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute,
             .brightnessUp, .brightnessDown: .media
        }
    }

    public var title: String {
        switch self {
        case .none: "Nothing"
        case .arrowUp: "Up Arrow"
        case .arrowDown: "Down Arrow"
        case .arrowLeft: "Left Arrow"
        case .arrowRight: "Right Arrow"
        case .returnKey: "Return"
        case .escape: "Escape"
        case .space: "Space"
        case .tab: "Tab"
        case .delete: "Delete"
        case .pageUp: "Page Up"
        case .pageDown: "Page Down"
        case .switchApp: "Switch to Last App"
        case .nextWindow: "Next Window of App"
        case .closeWindow: "Close Window"
        case .fullScreen: "Toggle Full Screen"
        case .spotlight: "Spotlight"
        case .pointerUp: "Move Pointer Up"
        case .pointerDown: "Move Pointer Down"
        case .pointerLeft: "Move Pointer Left"
        case .pointerRight: "Move Pointer Right"
        case .leftClick: "Click"
        case .rightClick: "Right Click"
        case .scrollUp: "Scroll Up"
        case .scrollDown: "Scroll Down"
        case .scrollLeft: "Scroll Left"
        case .scrollRight: "Scroll Right"
        case .playPause: "Play/Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .missionControl: "Mission Control"
        case .sleepDisplay: "Sleep Display"
        case .toggleMode: "Switch Mode"
        }
    }

    public var effect: Effect {
        switch self {
        case .none: .none
        case .arrowUp: .key(126, [])
        case .arrowDown: .key(125, [])
        case .arrowLeft: .key(123, [])
        case .arrowRight: .key(124, [])
        case .returnKey: .key(36, [])
        case .escape: .key(53, [])
        case .space: .key(49, [])
        case .tab: .key(48, [])
        case .delete: .key(51, [])
        case .pageUp: .key(116, [])
        case .pageDown: .key(121, [])
        case .switchApp: .key(48, .command)
        case .nextWindow: .key(50, .command)
        case .closeWindow: .key(13, .command)
        case .fullScreen: .key(3, [.command, .control])
        case .spotlight: .key(49, .command)
        case .pointerUp: .move(dx: 0, dy: -1)
        case .pointerDown: .move(dx: 0, dy: 1)
        case .pointerLeft: .move(dx: -1, dy: 0)
        case .pointerRight: .move(dx: 1, dy: 0)
        case .leftClick: .leftClick
        case .rightClick: .rightClick
        case .scrollUp: .scroll(dx: 0, dy: 1)
        case .scrollDown: .scroll(dx: 0, dy: -1)
        case .scrollLeft: .scroll(dx: 1, dy: 0)
        case .scrollRight: .scroll(dx: -1, dy: 0)
        case .playPause: .media(.play)
        case .nextTrack: .media(.next)
        case .previousTrack: .media(.previous)
        case .volumeUp: .media(.soundUp)
        case .volumeDown: .media(.soundDown)
        case .mute: .media(.mute)
        case .brightnessUp: .media(.brightnessUp)
        case .brightnessDown: .media(.brightnessDown)
        case .missionControl: .missionControl
        case .sleepDisplay: .sleepDisplay
        case .toggleMode: .toggleMode
        }
    }

    /// How a held button behaves.
    public enum Hold: Sendable { case once, repeats, continuous }

    public var hold: Hold {
        switch effect {
        case .move, .scroll: .continuous
        case .key(let code, let mods) where mods.isEmpty && [126, 125, 123, 124, 51, 116, 121].contains(code): .repeats
        case .media(let key) where [.soundUp, .soundDown, .brightnessUp, .brightnessDown].contains(key): .repeats
        default: .once
        }
    }

    /// What macOS itself does with a usage when the app cannot take the
    /// remote for itself: the remote then behaves as a keyboard, and posting
    /// the same action again would do it twice.
    public static func native(for usage: HIDUsage) -> RemoteAction? {
        switch (usage.page, usage.usage) {
        case (HIDUsage.keyboardPage, 0x52): .arrowUp
        case (HIDUsage.keyboardPage, 0x51): .arrowDown
        case (HIDUsage.keyboardPage, 0x50): .arrowLeft
        case (HIDUsage.keyboardPage, 0x4F): .arrowRight
        case (HIDUsage.keyboardPage, 0x28), (HIDUsage.keyboardPage, 0x58): .returnKey
        case (HIDUsage.keyboardPage, 0x29): .escape
        case (HIDUsage.keyboardPage, 0x2C): .space
        case (HIDUsage.keyboardPage, 0x2B): .tab
        case (HIDUsage.keyboardPage, 0x2A): .delete
        case (HIDUsage.consumerPage, 0xCD): .playPause
        case (HIDUsage.consumerPage, 0xB5): .nextTrack
        case (HIDUsage.consumerPage, 0xB6): .previousTrack
        case (HIDUsage.consumerPage, 0xE9): .volumeUp
        case (HIDUsage.consumerPage, 0xEA): .volumeDown
        case (HIDUsage.consumerPage, 0xE2): .mute
        default: nil
        }
    }
}
