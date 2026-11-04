import Foundation
import MacRemoteKit

/// Sample remotes and presses for snapshots: APP_SEED=1 with APP_STORE set.
/// Shows only what a real remote produces.
@MainActor
enum SampleData {
    static func fill(_ model: AppModel) {
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be set")
            return
        }
        model.monitor.show(sample: [
            .init(id: "fire", name: "Amazon Fire TV Remote", vendorID: 0x1949, productID: 0x0404,
                  transport: "Bluetooth Low Energy", isFireTV: true, isEnabled: true, isOpen: true, isSeized: true),
            .init(id: "kbd", name: "Magic Keyboard", vendorID: 0x05AC, productID: 0x029C,
                  transport: "Bluetooth", isFireTV: false, isEnabled: false),
            .init(id: "mx", name: "MX Master 3S", vendorID: 0x046D, productID: 0xB034,
                  transport: "Bluetooth Low Energy", isFireTV: false, isEnabled: false),
        ])
        let profile = model.engine.profile
        let presses: [(RemoteButton?, HIDUsage, TimeInterval)] = [
            (.select, .key(0x28), 4),
            (.down, .key(0x51), 9),
            (.down, .key(0x51), 11),
            (nil, .consumer(0x1A0), 40),
            (.playPause, .consumer(0xCD), 95),
            (.home, .consumer(0x223), 160),
        ]
        model.engine.show(lit: [.select, .right], sample: presses.map { button, usage, ago in
            let key = button.map(RemoteKey.init) ?? RemoteKey(usage: usage)
            return .init(key: key, usage: usage, action: profile.action(for: key, in: .navigation),
                         device: "Amazon Fire TV Remote", date: .now.addingTimeInterval(-ago), handledByMac: false)
        })
    }
}
