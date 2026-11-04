import AppKit
import Combine
import MacRemoteKit
import SwiftUI

/// The main window: a native sidebar (NSSplitViewController) with SwiftUI
/// pages. The window title follows the page.
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    private let model: AppModel
    private var titleWatch: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: BelowTitlebar.wrap(NSHostingController(
            rootView: SidebarView().environmentObject(model))))
        sidebar.minimumThickness = Width.sidebar - Space.xl
        sidebar.maximumThickness = Width.sidebar + Space.section + Space.lg
        sidebar.canCollapse = true
        let detail = NSSplitViewItem(viewController: BelowTitlebar.wrap(NSHostingController(
            rootView: DetailView()
                .environmentObject(model)
                .environmentObject(model.engine)
                .environmentObject(model.monitor)
                .environmentObject(model.permissions))))
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(detail)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 980, height: 680))
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") { window.center() }
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "Main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        titleWatch = model.$sidebar.sink { [weak window] page in window?.title = page.title }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        let opening = !window.isVisible
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // No focus ring on a control when the window opens.
        if opening { DispatchQueue.main.async { window.makeFirstResponder(nil) } }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }
}

/// On macOS 12 a SwiftUI view hosted in a full-size-content window ignores the
/// title bar, so the sidebar rows sit under the traffic lights. There the view
/// is pinned below the title bar and toolbar (the window's content layout guide).
/// macOS 13 and later lay it out correctly, so the controller is used as is.
final class BelowTitlebar: NSViewController {
    private let content: NSViewController
    private var top: NSLayoutConstraint?

    static func wrap(_ content: NSViewController) -> NSViewController {
        if #available(macOS 13, *) { return content }
        return BelowTitlebar(content)
    }

    private init(_ content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        let inner = content.view
        inner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inner)
        let top = inner.topAnchor.constraint(equalTo: view.topAnchor)
        self.top = top
        NSLayoutConstraint.activate([
            top,
            inner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard let guide = view.window?.contentLayoutGuide as? NSLayoutGuide else { return }
        top?.isActive = false
        let below = content.view.topAnchor.constraint(equalTo: guide.topAnchor)
        below.isActive = true
        top = below
    }
}

/// The Settings window (Command-Comma), one page. Called Preferences before macOS 13.
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let host = NSHostingController(rootView: SettingsView().environmentObject(model.engine))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = AppDelegate.settingsTitle.replacingOccurrences(of: "…", with: "")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.setContentSize(window.contentViewController?.view.fittingSize ?? .zero)
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }
}

/// The menu bar item: status, mode, pause, and the way back to the window.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private weak var delegate: AppDelegate?
    private var watch: AnyCancellable?

    init(model: AppModel, delegate: AppDelegate) {
        self.model = model
        self.delegate = delegate
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        watch = model.engine.$isEnabled.sink { [weak self] enabled in self?.updateIcon(enabled) }
    }

    private func updateIcon(_ enabled: Bool) {
        let name = Symbol.named(enabled ? "av.remote.fill" : "av.remote")
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacRemote")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let delegate else { return }
        menu.removeAllItems()
        menu.addItem(withTitle: model.monitor.activeRemoteName ?? "No Remote Connected", action: nil, keyEquivalent: "")
        if let battery = model.monitor.activeRemote?.battery {
            menu.addItem(withTitle: "Battery: \(battery.title)\(battery.isLow ? ", low" : "")", action: nil, keyEquivalent: "")
        }
        if !model.permissions.allGranted && !Store.isOverridden {
            menu.addItem(withTitle: "Needs permissions. Open MacRemote.", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        for mode in RemoteMode.allCases {
            let entry = delegate.item("\(mode.title) Mode", #selector(AppDelegate.selectMode(_:)))
            entry.representedObject = mode.rawValue
            entry.state = model.engine.mode == mode ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        delegate.addRemoteItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(delegate.item("Open MacRemote", #selector(AppDelegate.showMainWindow), "0"))
        menu.addItem(delegate.item(AppDelegate.settingsTitle, #selector(AppDelegate.showSettings), ","))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacRemote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}
