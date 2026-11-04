import Foundation

/// A remote's battery charge, as macOS reports it for Bluetooth LE remotes
/// (the `BatteryPercent` registry property) or as the remote sends it in a
/// HID report (Generic Device Controls page, Battery Strength usage).
public struct Battery: Equatable, Sendable {
    /// 0 to 100.
    public let percent: Int

    /// At or below this, the app suggests new batteries.
    public static let lowPercent = 20

    /// The registry property macOS sets on Bluetooth LE HID devices.
    public static let registryKey = "BatteryPercent"
    /// HID page 0x06 (Generic Device Controls), usage 0x20 (Battery Strength).
    public static let usagePage: UInt32 = 0x06
    public static let usage: UInt32 = 0x20

    public init?(percent: Int) {
        guard (0...100).contains(percent) else { return nil }
        self.percent = percent
    }

    /// Reads a registry property value, which arrives as an NSNumber.
    public init?(registryValue value: Any?) {
        guard let number = value as? NSNumber else { return nil }
        self.init(percent: number.intValue)
    }

    public var isLow: Bool { percent <= Self.lowPercent }

    /// "72%".
    public var title: String { "\(percent)%" }

    /// The SF Symbol for the charge. battery.75 and battery.50 need macOS 13;
    /// `Symbol.named` in the app falls back to the nearest older one.
    public var symbol: String {
        switch percent {
        case 88...: "battery.100"
        case 63..<88: "battery.75"
        case 38..<63: "battery.50"
        case 13..<38: "battery.25"
        default: "battery.0"
        }
    }
}
