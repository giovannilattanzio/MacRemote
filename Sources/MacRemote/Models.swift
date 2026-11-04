import Combine
import Foundation
import MacRemoteKit

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case remote, buttons, devices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: "Remote"
        case .buttons: "Buttons"
        case .devices: "Devices"
        }
    }

    var symbol: String {
        switch self {
        case .remote: "av.remote"
        case .buttons: "square.grid.3x3"
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
    let notifier = ConnectionNotifier(defaults: Store.defaults)

    @Published var sidebar: SidebarItem = .remote
    /// Keeps App Nap away. A napping app gets its timers slowed to seconds,
    /// and Pointer mode moves the pointer from a 120 Hz timer.
    private var activity: NSObjectProtocol?

    init(sink: EffectSink = EventSynth()) {
        engine = RemoteEngine(defaults: Store.defaults, sink: sink)
        monitor = HIDMonitor(defaults: Store.defaults)
        monitor.onInput = { [engine] usage, pressed, device in
            engine.handle(usage: usage, pressed: pressed, exclusive: device.isExclusive, from: device.name)
        }
        monitor.onConnection = { [notifier] device, connected in
            notifier.connection(device, connected: connected)
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
        permissions.onChange = { [monitor, permissions] in
            if permissions.inputMonitoring { monitor.start() }
        }
        permissions.refresh()
        if permissions.inputMonitoring { monitor.start() }
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
