import MacRemoteKit
import SwiftUI

/// The menu bar item's menu: status, mode, pause, and a way back to the window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var engine = model.engine
        Text(model.activeRemoteName ?? "No Remote Connected")
        if !model.permissions.allGranted && !Store.isOverridden {
            Text("Needs permissions. Open MacRemote.")
        }
        Divider()
        Picker("Mode", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
            ForEach(RemoteMode.allCases) { mode in
                Text("\(mode.title) Mode").tag(mode)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Toggle("Use Remote", isOn: $engine.isEnabled)
            .keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button("Open MacRemote") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit MacRemote") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
