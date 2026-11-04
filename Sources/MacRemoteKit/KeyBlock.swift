import Foundation

/// Stops macOS from acting on a remote's own key presses, so only MacRemote
/// responds to them. Used when the remote cannot be opened exclusively, which
/// is the norm for keyboard-class remotes like Fire TV remotes.
///
/// It sets the device's UserKeyMapping with `hidutil` (no admin rights
/// needed): every key maps to usage 0, which macOS ignores. The mapping sits
/// above the raw HID values the app reads, so the app still sees every press.
/// It lasts until it is cleared, the remote reconnects, or the Mac restarts.
public enum KeyBlock {
    /// Every usage macOS could act on: all keyboard keys, plus the remote's media and system buttons.
    public static var blockedUsages: [HIDUsage] {
        let keys = (0x04...0xFF).map { HIDUsage.key(UInt32($0)) }
        let others = RemoteButton.allCases.flatMap(\.usages).filter { $0.page != HIDUsage.keyboardPage }
        return keys + others
    }

    /// The hidutil value for one usage: page in the upper 32 bits, usage in the lower.
    public static func code(_ usage: HIDUsage) -> UInt64 {
        UInt64(usage.page) << 32 | UInt64(usage.usage)
    }

    /// `--matching` for one device.
    public static func matching(vendorID: Int, productID: Int) -> String {
        #"{"VendorID":\#(vendorID),"ProductID":\#(productID)}"#
    }

    /// `--set` that blocks every usage, or clears the mapping.
    public static func setting(blocked: Bool) -> String {
        guard blocked else { return #"{"UserKeyMapping":[]}"# }
        let pairs = blockedUsages.map {
            #"{"HIDKeyboardModifierMappingSrc":\#(code($0)),"HIDKeyboardModifierMappingDst":\#(code(.key(0)))}"#
        }
        return #"{"UserKeyMapping":["# + pairs.joined(separator: ",") + "]}"
    }
}
