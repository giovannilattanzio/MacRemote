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

    /// A HID Battery Strength value, scaled from the element's logical range
    /// to a percentage. Fire TV remotes declare 0 to 255 but send a plain
    /// percentage (a full remote sends 100), so for them pass `isPercent`.
    public init?(raw: Int, logicalMin: Int, logicalMax: Int, isPercent: Bool = false) {
        if isPercent {
            self.init(percent: raw)
            return
        }
        guard logicalMax > logicalMin, (logicalMin...logicalMax).contains(raw) else { return nil }
        let scaled = Double(raw - logicalMin) * 100 / Double(logicalMax - logicalMin)
        self.init(percent: Int(scaled.rounded()))
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
