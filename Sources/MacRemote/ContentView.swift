import MacRemoteKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: Binding<SidebarItem?>(get: { model.sidebar }, set: { if let page = $0 { model.sidebar = page } })) {
            ForEach(SidebarItem.allCases) { page in
                Label(page.title, systemImage: Symbol.named(page.symbol))
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
    }
}

struct DetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.sidebar {
        case .remote: RemotePage()
        case .buttons: ButtonsPage()
        case .devices: DevicesPage()
        }
    }
}

// MARK: - Remote

struct RemotePage: View {
    @EnvironmentObject private var engine: RemoteEngine
    @EnvironmentObject private var monitor: HIDMonitor
    @EnvironmentObject private var permissions: Permissions

    private var canSearch: Bool { permissions.inputMonitoring || Store.isOverridden }

    var body: some View {
        Page {
            Card(footer: engine.mode == .navigation
                 ? "The D-pad sends arrow keys and Select presses Return. Press Menu on the remote to switch to Pointer."
                 : "The D-pad moves the pointer and Select clicks. Hold Select while moving to drag. Press Menu to switch back.") {
                status
                CardDivider()
                Row(title: "Mode") {
                    Picker("Mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
                        ForEach(RemoteMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if !permissions.allGranted && !Store.isOverridden || ProcessInfo.processInfo.environment["APP_SEED"] == "1" {
                PermissionsCard()
            }

            if monitor.activeRemoteName == nil && canSearch {
                PairingCard()
            }

            Card(title: "Last Buttons Pressed") {
                if engine.recent.isEmpty {
                    Row(title: "Press a button on the remote to see what it does.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(engine.recent.enumerated()), id: \.element.id) { index, press in
                        if index > 0 { CardDivider() }
                        PressRow(press: press)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let name = monitor.activeRemoteName {
            Row(title: name, subtitle: engine.isEnabled ? "Connected and in use" : "Connected, paused",
                symbol: "av.remote.fill") {
                Toggle("Use Remote", isOn: $engine.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        } else if !canSearch {
            Row(title: "Looking for Remotes Is Off",
                subtitle: "Allow Input Monitoring below so MacRemote can find the remote.",
                symbol: "av.remote")
        } else {
            Row(title: "No Remote Connected", subtitle: "Pair a Fire TV remote in Bluetooth settings. Steps below.",
                symbol: "av.remote")
        }
    }
}

private struct PressRow: View {
    let press: RemoteEngine.Press

    var body: some View {
        Row(title: press.key.title,
            subtitle: press.action == .none ? "Not set · \(press.usage.description)" : press.action.title,
            symbol: press.key.symbol) {
            Text(press.date, style: .time)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help("\(press.device), HID usage \(press.usage.description)")
    }
}

struct PermissionsCard: View {
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        Card(title: "Permissions",
             footer: "Turn MacRemote on in System Settings > Privacy & Security (System Preferences > Security & Privacy > Privacy on macOS 12). This page updates by itself.") {
            row("Input Monitoring", detail: "Reads the remote's buttons.",
                granted: permissions.inputMonitoring) { permissions.requestInputMonitoring() }
            CardDivider()
            row("Accessibility", detail: "Presses keys and moves the pointer.",
                granted: permissions.accessibility) { permissions.requestAccessibility() }
        }
    }

    private func row(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        Row(title: title, subtitle: detail) {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: request)
            }
        }
    }
}

struct PairingCard: View {
    var body: some View {
        Card(title: "Pair a Fire TV Remote") {
            step(1, "Open Bluetooth settings on this Mac.")
            CardDivider()
            step(2, "Unplug or turn off the Fire TV it was paired with, so it does not grab the remote back.")
            CardDivider()
            step(3, "Hold Home on the remote for about 10 seconds, until its light blinks.")
            CardDivider()
            step(4, "Click Connect next to the remote when it shows in the list. If the Keyboard Setup Assistant opens, close it.")
            CardDivider()
            Row(title: "") {
                Button("Open Bluetooth Settings") {
                    let modern = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!
                    let legacy = URL(fileURLWithPath: "/System/Library/PreferencePanes/Bluetooth.prefPane")
                    if #available(macOS 13, *) { NSWorkspace.shared.open(modern) } else { NSWorkspace.shared.open(legacy) }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Row(title: text, symbol: "\(number).circle.fill")
    }
}

// MARK: - Buttons

struct ButtonsPage: View {
    @EnvironmentObject private var engine: RemoteEngine

    var body: some View {
        VStack(spacing: 0) {
            Table(engine.profile.keys) {
                TableColumn("Button") { key in
                    Label(key.title, systemImage: Symbol.named(key.symbol))
                }
                .width(min: 140, ideal: 180)
                TableColumn("Navigation Mode") { key in
                    ActionPicker(engine: engine, key: key, mode: .navigation)
                }
                TableColumn("Pointer Mode") { key in
                    ActionPicker(engine: engine, key: key, mode: .pointer)
                }
            }
            Divider()
            HStack {
                Text("Buttons the app does not know show up here after you press them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { engine.restoreDefaults() }
                    .help("Set every button back to what it did at first (Shift-Command-R)")
                    .disabled(engine.profile == .standard)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.md)
        }
    }
}

/// Table cells do not inherit environment objects, so the engine comes in directly.
struct ActionPicker: View {
    @ObservedObject var engine: RemoteEngine
    let key: RemoteKey
    let mode: RemoteMode

    var body: some View {
        Picker("Action", selection: Binding(
            get: { engine.profile.action(for: key, in: mode) },
            set: { engine.profile.set($0, for: key, in: mode) }
        )) {
            Text(RemoteAction.none.title).tag(RemoteAction.none)
            ForEach(RemoteAction.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(RemoteAction.allCases.filter { $0.group == group && $0 != .none }) { action in
                        Text(action.title).tag(action)
                    }
                }
            }
        }
        .labelsHidden()
    }
}

// MARK: - Devices

struct DevicesPage: View {
    @EnvironmentObject private var monitor: HIDMonitor
    @EnvironmentObject private var permissions: Permissions

    private var fireTV: [HIDMonitor.Device] { monitor.devices.filter(\.isFireTV) }
    private var others: [HIDMonitor.Device] { monitor.devices.filter { !$0.isFireTV } }

    var body: some View {
        if monitor.devices.isEmpty {
            EmptyState(title: "No Devices", symbol: "dot.radiowaves.left.and.right",
                       message: permissions.inputMonitoring || Store.isOverridden
                       ? "Pair a remote in Bluetooth settings and it shows here."
                       : "Allow Input Monitoring on the Remote page to see devices.")
        } else {
            Page {
                Card(title: "Fire TV Remotes", footer: "Fire TV remotes are used as soon as they connect.") {
                    if fireTV.isEmpty {
                        Row(title: "No Fire TV remote connected.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(fireTV.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { CardDivider() }
                        DeviceRow(device: device)
                    }
                }
                if !others.isEmpty {
                    Card(title: "Other Devices",
                         footer: "Turn on another remote to control the Mac with it. Turning on your keyboard makes it act like a remote.") {
                        ForEach(Array(others.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { CardDivider() }
                            DeviceRow(device: device)
                        }
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var monitor: HIDMonitor
    let device: HIDMonitor.Device

    private var status: String {
        guard device.isEnabled else { return device.transport.isEmpty ? "Not used" : "\(device.transport) · Not used" }
        guard device.isOpen else { return "Could not be opened" }
        return device.isSeized ? "In use" : "In use, shared with macOS"
    }

    var body: some View {
        Row(title: device.name, subtitle: status) {
            Toggle("Use as Remote", isOn: Binding(
                get: { device.isEnabled },
                set: { monitor.setEnabled($0, for: device.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .help(device.isEnabled && !device.isSeized
              ? "macOS also reads this device, so its arrow, Return, and media keys act on their own too."
              : String(format: "Vendor %04X, product %04X", device.vendorID, device.productID))
    }
}
