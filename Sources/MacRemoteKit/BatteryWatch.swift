import Foundation

/// Decides when a remote's battery is worth a notification: once when it
/// first reads low, and not again until the charge goes back up past
/// `rearmPercent` (new batteries). A remote that reconnects while still low
/// stays quiet, because readings are kept by remote id for the whole run.
public struct BatteryWatch: Sendable {
    /// A charge above this means the batteries were replaced.
    public static let rearmPercent = Battery.lowPercent + 10

    private var warned: Set<String> = []

    public init() {}

    /// A remote reported its charge. Returns the notice to show, if any.
    public mutating func reading(id: String, name: String, battery: Battery) -> RemoteNotice? {
        if battery.percent > Self.rearmPercent {
            warned.remove(id)
            return nil
        }
        guard battery.isLow, warned.insert(id).inserted else { return nil }
        return RemoteNotice(.lowBattery(battery.percent), name: name)
    }
}
