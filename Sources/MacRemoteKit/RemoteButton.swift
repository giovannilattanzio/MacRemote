import Foundation

/// One HID usage: a usage page and a usage inside it, as a remote reports a
/// button. Keyboard page 0x07, Consumer page 0x0C, Generic Desktop 0x01.
public struct HIDUsage: Hashable, Codable, Sendable, CustomStringConvertible {
    public let page: UInt32
    public let usage: UInt32

    public init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }

    public static let keyboardPage: UInt32 = 0x07
    public static let consumerPage: UInt32 = 0x0C
    public static let genericDesktopPage: UInt32 = 0x01

    public static func key(_ usage: UInt32) -> HIDUsage { HIDUsage(page: keyboardPage, usage: usage) }
    public static func consumer(_ usage: UInt32) -> HIDUsage { HIDUsage(page: consumerPage, usage: usage) }
    public static func desktop(_ usage: UInt32) -> HIDUsage { HIDUsage(page: genericDesktopPage, usage: usage) }

    /// "0C:00CD"
    public var description: String { String(format: "%02X:%04X", page, usage) }

    /// True for usages that are real buttons. Keyboard reports carry
    /// placeholder usages (0x00-0x03 and the array slot 0xFFFFFFFF) that are not.
    /// Fire TV remotes send Back as keyboard usage 0xF1, above the standard keys.
    public var isButton: Bool {
        switch page {
        case Self.keyboardPage: (0x04...0xFF).contains(usage)
        case Self.consumerPage: usage != 0 && usage != 0x01 && usage != 0xFFFF_FFFF
        case Self.genericDesktopPage: (0x81...0x93).contains(usage)
        default: page >= 0x09 && usage != 0xFFFF_FFFF
        }
    }
}

/// The buttons of an Amazon Fire TV (Alexa Voice) remote. Different
/// generations report some buttons on different usages, so each button
/// lists every usage seen for it.
public enum RemoteButton: String, CaseIterable, Codable, Sendable {
    case up, down, left, right, select
    case back, home, menu
    case playPause, rewind, fastForward
    case volumeUp, volumeDown, mute
    case power, voice, guide

    public var title: String {
        switch self {
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .select: "Select"
        case .back: "Back"
        case .home: "Home"
        case .menu: "Menu"
        case .playPause: "Play/Pause"
        case .rewind: "Rewind"
        case .fastForward: "Fast Forward"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .power: "Power"
        case .voice: "Alexa"
        case .guide: "Guide"
        }
    }

    /// SF Symbol for the button.
    public var symbol: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .select: "circle.circle"
        case .back: "arrow.uturn.backward"
        case .home: "house"
        case .menu: "line.3.horizontal"
        case .playPause: "playpause"
        case .rewind: "backward"
        case .fastForward: "forward"
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .mute: "speaker.slash"
        case .power: "power"
        case .voice: "mic"
        case .guide: "list.bullet.rectangle"
        }
    }

    public var usages: [HIDUsage] {
        switch self {
        case .up: [.key(0x52), .consumer(0x42)]
        case .down: [.key(0x51), .consumer(0x43)]
        case .left: [.key(0x50), .consumer(0x44)]
        case .right: [.key(0x4F), .consumer(0x45)]
        case .select: [.key(0x28), .key(0x58), .consumer(0x41)]
        case .back: [.consumer(0x224), .key(0x29), .key(0xF1)]
        case .home: [.consumer(0x223), .key(0x4A)]
        case .menu: [.consumer(0x40), .key(0x76), .key(0x65)]
        case .playPause: [.consumer(0xCD), .consumer(0xB0), .consumer(0xB1)]
        case .rewind: [.consumer(0xB4), .consumer(0xB6)]
        case .fastForward: [.consumer(0xB3), .consumer(0xB5)]
        case .volumeUp: [.consumer(0xE9)]
        case .volumeDown: [.consumer(0xEA)]
        case .mute: [.consumer(0xE2)]
        case .power: [.consumer(0x30), .desktop(0x81), .desktop(0x82)]
        case .voice: [.consumer(0x221), .consumer(0xCF)]
        case .guide: [.consumer(0x8D)]
        }
    }

    private static let byUsage: [HIDUsage: RemoteButton] = {
        var table: [HIDUsage: RemoteButton] = [:]
        for button in allCases { for usage in button.usages { table[usage] = button } }
        return table
    }()

    public init?(usage: HIDUsage) {
        guard let button = Self.byUsage[usage] else { return nil }
        self = button
    }
}

/// The key a mapping is stored under: a known button, or the raw usage of a
/// button this app does not know yet (newer remotes add app buttons).
public struct RemoteKey: Hashable, Codable, Sendable, Identifiable, Comparable {
    public let raw: String
    public var id: String { raw }

    public init(_ button: RemoteButton) { raw = button.rawValue }

    public init(usage: HIDUsage) {
        if let button = RemoteButton(usage: usage) {
            raw = button.rawValue
        } else {
            raw = "usage:\(usage)"
        }
    }

    public init(raw: String) { self.raw = raw }

    public var button: RemoteButton? { RemoteButton(rawValue: raw) }

    public var title: String { button?.title ?? "Button \(raw.replacingOccurrences(of: "usage:", with: ""))" }
    public var symbol: String { button?.symbol ?? "circle.dashed" }

    /// Known buttons in remote order first, then learned ones by usage.
    public static func < (a: RemoteKey, b: RemoteKey) -> Bool {
        let order = RemoteButton.allCases
        switch (a.button, b.button) {
        case let (x?, y?): return order.firstIndex(of: x)! < order.firstIndex(of: y)!
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return a.raw < b.raw
        }
    }
}

/// Amazon's Bluetooth vendor id (Lab126) and the names Fire TV remotes use.
public enum FireTVRemote {
    public static let vendorIDs: Set<Int> = [0x1949, 0x0171]

    public static func isFireTVRemote(vendorID: Int, product: String) -> Bool {
        if vendorIDs.contains(vendorID) { return true }
        let name = product.lowercased()
        return ["fire tv", "firetv", "amazon", "aftv", "alexa voice remote"].contains { name.contains($0) }
    }
}
