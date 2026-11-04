import MacRemoteKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch model.sidebar ?? .remote {
            case .remote: RemotePage()
            case .buttons: ButtonsPage()
            case .devices: DevicesPage()
            }
        }
        .noInitialFocus()
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}

// MARK: - Remote

struct RemotePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var engine = model.engine
        Form {
            Section {
                LabeledContent {
                    Toggle("Use Remote", isOn: $engine.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                } label: {
                    if let name = model.activeRemoteName {
                        Label(name, systemImage: "av.remote.fill")
                        Text(engine.isEnabled ? "Connected and in use" : "Connected, paused")
                    } else if !model.permissions.inputMonitoring && !Store.isOverridden {
                        Label("Looking for Remotes Is Off", systemImage: "av.remote")
                        Text("Allow Input Monitoring below so MacRemote can find the remote.")
                    } else {
                        Label("No Remote Connected", systemImage: "av.remote")
                        Text("Pair a Fire TV remote in Bluetooth settings. Steps below.")
                    }
                }
                Picker("Mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
                    ForEach(RemoteMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(model.engine.mode == .navigation
                     ? "The D-pad sends arrow keys and Select presses Return. Press Menu on the remote to switch to Pointer."
                     : "The D-pad moves the pointer and Select clicks. Hold Select while moving to drag. Press Menu to switch back.")
                    .foregroundStyle(.secondary)
            }

            if !model.permissions.allGranted {
                PermissionsSection()
            }

            if model.activeRemoteName == nil && (model.permissions.inputMonitoring || Store.isOverridden) {
                PairingSection()
            }

            Section("Last Buttons Pressed") {
                if model.engine.recent.isEmpty {
                    Text("Press a button on the remote to see what it does.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.engine.recent) { press in
                        PressRow(press: press)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Remote")
    }
}

private struct PressRow: View {
    let press: RemoteEngine.Press

    var body: some View {
        LabeledContent {
            Text(press.date, style: .time)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } label: {
            Label(press.key.title, systemImage: press.key.symbol)
            Text(press.action == .none ? "Not set · \(press.usage.description)" : press.action.title)
        }
        .help("\(press.device), HID usage \(press.usage.description)")
    }
}

struct PermissionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            row("Input Monitoring", detail: "Reads the remote's buttons.",
                granted: model.permissions.inputMonitoring) { model.permissions.requestInputMonitoring() }
            row("Accessibility", detail: "Presses keys and moves the pointer.",
                granted: model.permissions.accessibility) { model.permissions.requestAccessibility() }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Turn MacRemote on in System Settings > Privacy & Security. This page updates by itself.")
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: request)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

struct PairingSection: View {
    var body: some View {
        Section {
            step(1, "Open System Settings > Bluetooth on this Mac.")
            step(2, "Unplug or turn off the Fire TV it was paired with, so it does not grab the remote back.")
            step(3, "Hold Home on the remote for about 10 seconds, until its light blinks.")
            step(4, "Click Connect next to the remote when it shows in the list.")
            Button("Open Bluetooth Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
            }
        } header: {
            Text("Pair a Fire TV Remote")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
        }
    }
}

// MARK: - Buttons

struct ButtonsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        Table(engine.profile.keys) {
            TableColumn("Button") { key in
                Label(key.title, systemImage: key.symbol)
            }
            .width(min: 140, ideal: 180)
            TableColumn("Navigation Mode") { key in
                ActionPicker(engine: engine, key: key, mode: .navigation)
            }
            TableColumn("Pointer Mode") { key in
                ActionPicker(engine: engine, key: key, mode: .pointer)
            }
        }
        .navigationTitle("Buttons")
        .toolbar {
            ToolbarItem {
                Button("Restore Defaults", systemImage: "arrow.counterclockwise") { engine.restoreDefaults() }
                    .help("Set every button back to what it did at first (Shift-Command-R)")
                    .disabled(engine.profile == .standard)
            }
        }
    }
}

struct ActionPicker: View {
    let engine: RemoteEngine
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
    @Environment(AppModel.self) private var model

    private var fireTV: [HIDMonitor.Device] { model.monitor.devices.filter(\.isFireTV) }
    private var others: [HIDMonitor.Device] { model.monitor.devices.filter { !$0.isFireTV } }

    var body: some View {
        Group {
            if model.monitor.devices.isEmpty {
                ContentUnavailableView {
                    Label("No Devices", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text(model.permissions.inputMonitoring || Store.isOverridden
                         ? "Pair a remote in Bluetooth settings and it shows here."
                         : "Allow Input Monitoring on the Remote page to see devices.")
                }
            } else {
                Form {
                    Section {
                        if fireTV.isEmpty {
                            Text("No Fire TV remote connected.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(fireTV) { DeviceRow(device: $0) }
                    } header: {
                        Text("Fire TV Remotes")
                    } footer: {
                        Text("Fire TV remotes are used as soon as they connect.")
                            .foregroundStyle(.secondary)
                    }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { DeviceRow(device: $0) }
                        } header: {
                            Text("Other Devices")
                        } footer: {
                            Text("Turn on another remote to control the Mac with it. Turning on your keyboard makes it act like a remote.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Devices")
    }
}

private struct DeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: HIDMonitor.Device

    private var status: String {
        guard device.isEnabled else { return device.transport.isEmpty ? "Not used" : "\(device.transport) · Not used" }
        guard device.isOpen else { return "Could not be opened" }
        return device.isSeized ? "In use" : "In use, shared with macOS"
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { device.isEnabled },
            set: { model.monitor.setEnabled($0, for: device.id) }
        )) {
            Text(device.name)
            Text(status)
        }
        .toggleStyle(.switch)
        .help(device.isEnabled && !device.isSeized
              ? "macOS also reads this device, so its arrow, Return, and media keys act on their own too."
              : String(format: "Vendor %04X, product %04X", device.vendorID, device.productID))
    }
}
