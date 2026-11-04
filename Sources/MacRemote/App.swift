import AppKit
import SwiftUI

// MacRemote
//   MacRemote                      the app
//   APP_STORE=<file> MacRemote     test mode: settings go to a throwaway domain, no remote is opened
//   APP_SNAPSHOT=<dir> MacRemote   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 MacRemote           show sample remotes and presses (tools/snap.sh)
//   MacRemote --selftest           run the self-test and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> MacRemote      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 MacRemote           draw the 8 pt grid and the layout probes over the window

@main
struct MacRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("MacRemote", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
                .defaultAppStorage(Store.defaults)
        }
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {}
            RemoteCommands(model: model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(systemName: model.engine.isEnabled ? "av.remote.fill" : "av.remote")
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
                .defaultAppStorage(Store.defaults)
        }
        .windowResizability(.contentSize)
    }
}

struct RemoteCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Remote") {
            Button(model.engine.isEnabled ? "Pause Remote" : "Resume Remote") {
                model.engine.isEnabled.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Switch to \(model.engine.mode.next.title) Mode") {
                model.engine.toggleMode()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Restore Default Buttons") { model.engine.restoreDefaults() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        AppModel.shared.start()
    }

    /// The remote keeps working from the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        SelfTest.requested || Snapshot.requested
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
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
