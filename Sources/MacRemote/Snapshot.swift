import AppKit
import IOKit.pwr_mgt

/// Screenshot mode for agents.
///   APP_STORE=test APP_SNAPSHOT=/tmp/shots /Applications/MacRemote.app/Contents/MacOS/MacRemote
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-light.png and settings-dark.png, then quits.
/// APP_SNAPSHOT_PAGES=remote,buttons limits the pages. Add "settings" to include Settings.
@MainActor
enum Snapshot {
    static var requested: Bool { !(ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty }

    static func runIfRequested(delegate: AppDelegate) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real settings.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task { @MainActor in
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            await pause(1.5)
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    delegate.model.sidebar = page
                    await pause(0.8)
                    capture(delegate.mainWindow.window, to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if only == nil || only?.contains("settings") == true {
                delegate.showSettings()
                await pause(1)
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    await pause(0.8)
                    capture(delegate.settingsWindow.window, to: "\(dir)/settings-\(mode).png")
                }
            }
            print("SNAPSHOT done \(dir)")
            NSApp.terminate(nil)
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Captures the real window with screencapture, so sidebars and materials
    /// look exactly as on screen. That needs Screen Recording permission for
    /// the app that started this one (your terminal, or Claude). Without it,
    /// falls back to drawing the view hierarchy, which leaves sidebars blank.
    private static func capture(_ window: NSWindow?, to path: String) {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window else {
            print("SNAPSHOT no window")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission)")
        }
    }
}
