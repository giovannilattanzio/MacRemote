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

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    static let shared = AppModel()

    let engine: RemoteEngine
    let monitor: HIDMonitor
    let permissions = Permissions()
    let hud = ModeHUD()

    var sidebar: SidebarItem? = .remote
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(sink: EffectSink = EventSynth()) {
        engine = RemoteEngine(defaults: Store.defaults, sink: sink)
        monitor = HIDMonitor(defaults: Store.defaults)
        monitor.onInput = { [engine] usage, pressed, device in
            engine.handle(usage: usage, pressed: pressed, exclusive: device.isSeized, from: device.name)
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
        permissions.refresh()
        permissions.onChange = { [monitor, permissions] in
            if permissions.inputMonitoring { monitor.start() }
        }
        if permissions.inputMonitoring { monitor.start() }
    }

    /// The name of the first connected remote in use, for status lines.
    var activeRemoteName: String? {
        monitor.devices.first { $0.isEnabled && $0.isOpen }?.name
    }
}
