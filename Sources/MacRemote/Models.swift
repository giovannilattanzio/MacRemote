import Combine
import Foundation
import MacRemoteKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case remote, buttons, apps, devices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: "Remote"
        case .buttons: "Buttons"
        case .apps: "Apps"
        case .devices: "Devices"
        }
    }

    var symbol: String {
        switch self {
        case .remote: "av.remote"
        case .buttons: "square.grid.3x3"
        case .apps: "macwindow.on.rectangle"
        case .devices: "dot.radiowaves.left.and.right"
        }
    }
}

/// App-wide state that menus, windows, and views share.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine: RemoteEngine
    let monitor: HIDMonitor
    let permissions = Permissions()
    let hud = ModeHUD()
    let notifier = RemoteNotifier(defaults: Store.defaults)
    let keyFilter = RemoteKeyFilter()

    @Published var sidebar: SidebarItem = .remote
    /// Keeps App Nap away. A napping app gets its timers slowed to seconds,
    /// and Pointer mode moves the pointer from a 120 Hz timer.
    private var activity: NSObjectProtocol?

    init(sink: EffectSink = EventSynth()) {
        engine = RemoteEngine(defaults: Store.defaults, sink: sink)
        monitor = HIDMonitor(defaults: Store.defaults)
        monitor.onInput = { [engine, keyFilter] usage, pressed, device in
            if engine.isEnabled, !device.isSeized { keyFilter.remote(usage, pressed: pressed) }
            engine.handle(usage: usage, pressed: pressed, exclusive: device.isExclusive, from: device.name)
        }
        monitor.onConnection = { [notifier] device, connected in
            notifier.connection(device, connected: connected)
        }
        monitor.onBattery = { [notifier] device in notifier.battery(device) }
        keyFilter.remoteShared = { [engine, monitor] in
            engine.isEnabled && monitor.devices.contains { $0.isEnabled && $0.isOpen && !$0.isSeized }
        }
        keyFilter.keysBlocked = { [engine, monitor] in
            engine.isEnabled && monitor.devices.contains { $0.isEnabled && $0.isOpen && $0.keysBlocked }
        }
        engine.onModeChange = { [hud] mode in
            if Store.defaults.object(forKey: "showModeHUD") as? Bool ?? true { hud.show(mode) }
        }
    }

    /// Opens the remotes. Test runs never touch real hardware.
    func start() {
        if ProcessInfo.processInfo.environment["APP_SEED"] == "1" {
            SampleData.fill(self)
        }
        guard !Store.isOverridden else { return }
        notifier.useNotificationCenter()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Turning remote control presses into pointer and key events")
        permissions.onChange = { [monitor, permissions, keyFilter] in
            if permissions.inputMonitoring { monitor.start() }
            if permissions.accessibility { keyFilter.start() }
        }
        permissions.refresh()
        if permissions.inputMonitoring { monitor.start() }
        if permissions.accessibility { keyFilter.start() }
    }
}

/// Where settings live. Test, snapshot, and self-test runs use a throwaway
/// domain and never touch the real settings or a real remote.
enum Store {
    /// True when APP_STORE is set (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static let defaults: UserDefaults = {
        guard isOverridden else { return .standard }
        let suite = "com.gilattanzio.macremote.test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}
