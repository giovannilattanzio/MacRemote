import AppKit
import MacRemoteKit

// MacRemote
//   MacRemote                      the app
//   APP_STORE=<anything> MacRemote test mode: settings go to a throwaway domain, no remote is opened
//   APP_SNAPSHOT=<dir> MacRemote   save a PNG of every page and Settings in light and dark mode, then quit
//   APP_SEED=1 MacRemote           show sample remotes and presses (tools/snap.sh)
//   MacRemote --selftest           run the self-test and quit with 0 or 1 (tools/selftest.sh)
//
// The app shell is AppKit (windows, sidebar, menus, menu bar item) so it
// behaves the same from macOS 12 to 26. Page content is SwiftUI.

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel.shared
    private(set) lazy var mainWindow = MainWindowController(model: model)
    private(set) lazy var settingsWindow = SettingsWindowController(model: model)
    private var statusItem: StatusItemController?
    private let remoteMenu = NSMenu(title: "Remote")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMainMenu()
        statusItem = StatusItemController(model: model, delegate: self)
        model.notifier.onOpen = { [weak self] in self?.showMainWindow() }
        model.start()
        showMainWindow()
        SelfTest.runIfRequested(model: model)
        Snapshot.runIfRequested(delegate: self)
    }

    /// The remote keeps working from the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        SelfTest.requested || Snapshot.requested
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        model.monitor.clearBlocking()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }

    // MARK: Actions (menus, menu bar item)

    @objc func showMainWindow() {
        mainWindow.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        settingsWindow.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Where donations go. Shown in Settings, the Help menu, and the README.
    static let donateURL = URL(string: "https://paypal.me/giovannilattanzio")!

    @objc func donate() { NSWorkspace.shared.open(Self.donateURL) }

    @objc func toggleEnabled() { model.engine.isEnabled.toggle() }
    @objc func toggleMode() { model.engine.toggleMode() }
    @objc func toggleKeyboard() { model.keyboard.toggle() }
    @objc func restoreDefaults() { model.engine.restoreDefaults() }
    @objc func addApp() {
        model.sidebar = .apps
        showMainWindow()
        AppChooser.chooseFromDisk(into: model.engine)
    }

    @objc func selectMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? String, let new = RemoteMode(rawValue: mode) {
            model.engine.setMode(new)
        }
    }

    @objc func showPage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let page = SidebarItem(rawValue: raw) {
            model.sidebar = page
            showMainWindow()
        }
    }

    // MARK: Menus

    /// "Settings" since macOS 13, "Preferences" before, as the system says it.
    static var settingsTitle: String {
        if #available(macOS 13, *) { return "Settings…" }
        return "Preferences…"
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About MacRemote", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item(Self.settingsTitle, #selector(showSettings), ","))
        app.addItem(.separator())
        let services = NSMenu()
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide MacRemote", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit MacRemote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "MacRemote", action: nil, keyEquivalent: "").submenu = app

        let view = NSMenu(title: "View")
        for (index, page) in SidebarItem.allCases.enumerated() {
            let entry = item(page.title, #selector(showPage(_:)), "\(index + 1)")
            entry.representedObject = page.rawValue
            view.addItem(entry)
        }
        view.addItem(.separator())
        let sidebar = view.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view

        remoteMenu.delegate = self
        main.addItem(withTitle: "Remote", action: nil, keyEquivalent: "").submenu = remoteMenu

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(.separator())
        window.addItem(item("MacRemote", #selector(showMainWindow), "0"))
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("Donate to MacRemote…", #selector(donate), "d", shift: true))
        main.addItem(withTitle: "Help", action: nil, keyEquivalent: "").submenu = help
        NSApp.helpMenu = help

        return main
    }

    /// The Remote menu: rebuilt each time it opens, so titles show the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addRemoteItems(to: menu)
    }

    /// Shared by the Remote menu and the menu bar item.
    func addRemoteItems(to menu: NSMenu) {
        let engine = model.engine
        menu.addItem(item(engine.isEnabled ? "Pause Remote" : "Resume Remote", #selector(toggleEnabled), "p", shift: true))
        menu.addItem(item("Switch to \(engine.mode.next.title) Mode", #selector(toggleMode), "m", shift: true))
        menu.addItem(item(model.keyboard.isOpen ? "Hide Keyboard" : "Show Keyboard", #selector(toggleKeyboard), "k", shift: true))
        menu.addItem(.separator())
        menu.addItem(item("Restore Default Buttons", #selector(restoreDefaults), "r", shift: true))
        menu.addItem(item("Add App…", #selector(addApp), "a", shift: true))
    }

    func item(_ title: String, _ action: Selector, _ key: String = "", shift: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if shift { item.keyEquivalentModifierMask = [.command, .shift] }
        return item
    }
}
