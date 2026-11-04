import ServiceManagement
import SwiftUI

/// The Settings window's one page. Sized to its content.
struct SettingsView: View {
    @AppStorage("pointerSpeed", store: Store.defaults) private var pointerSpeed = 0.5
    @AppStorage("scrollSpeed", store: Store.defaults) private var scrollSpeed = 0.5
    @AppStorage("showModeHUD", store: Store.defaults) private var showModeHUD = true
    @AppStorage(RemoteNotifier.settingKey, store: Store.defaults) private var notifyConnections = true
    @AppStorage(RemoteNotifier.batterySettingKey, store: Store.defaults) private var notifyLowBattery = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            Card(title: "Pointer") {
                Row(title: "Pointer speed") { speed($pointerSpeed) }
                CardDivider()
                Row(title: "Scroll speed") { speed($scrollSpeed) }
            }
            Card(title: "General") {
                Row(title: "Show the mode on screen when it changes") {
                    Toggle("Show the mode on screen", isOn: $showModeHUD)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                CardDivider()
                Row(title: "Notify when a remote connects or disconnects") {
                    Toggle("Notify when a remote connects or disconnects", isOn: $notifyConnections)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                CardDivider()
                Row(title: "Notify when a remote's battery is low") {
                    Toggle("Notify when a remote's battery is low", isOn: $notifyLowBattery)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                CardDivider()
                OpenAtLoginRow()
            }
        }
        .padding(Space.margin)
        .frame(width: Width.settings)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func speed(_ value: Binding<Double>) -> some View {
        Slider(value: value, in: 0...1) {
            EmptyView()
        } minimumValueLabel: {
            Image(systemName: "tortoise")
        } maximumValueLabel: {
            Image(systemName: "hare")
        }
        .frame(width: Width.settings / 2)
    }
}

/// A login item needs SMAppService (macOS 13). On macOS 12 the row says where to add it by hand.
private struct OpenAtLoginRow: View {
    @State private var on = false

    var body: some View {
        if #available(macOS 13, *) {
            Row(title: "Open at login") {
                Toggle("Open at login", isOn: $on)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onAppear { on = SMAppService.mainApp.status == .enabled }
                    .onChange(of: on) { wanted in
                        guard !Store.isOverridden, wanted != (SMAppService.mainApp.status == .enabled) else { return }
                        do {
                            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            on = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        } else {
            Row(title: "Open at login",
                subtitle: "Add MacRemote in System Preferences > Users & Groups > Login Items.")
        }
    }
}
