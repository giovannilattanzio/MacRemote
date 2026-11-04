import Foundation
import MacRemoteKit
import UserNotifications

/// Posts a notification when a remote in use connects or disconnects,
/// unless turned off in Settings. ConnectionWatch decides which events count.
/// Clicking a notification opens the main window.
final class ConnectionNotifier: NSObject {
    /// The Settings switch.
    static let settingKey = "notifyConnections"

    /// Where notices go. The app posts to Notification Center; the self-test records them.
    var post: (ConnectionNotice) -> Void
    var onOpen: (() -> Void)?

    private var watch: ConnectionWatch
    private let clock: () -> TimeInterval
    private let defaults: UserDefaults

    init(defaults: UserDefaults, settle: TimeInterval = 3, startQuiet: TimeInterval = 3,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.clock = clock
        watch = ConnectionWatch(start: clock(), startQuiet: startQuiet, settle: settle)
        post = { _ in }
        super.init()
    }

    var isOn: Bool { defaults.object(forKey: Self.settingKey) as? Bool ?? true }

    func connection(_ device: HIDMonitor.Device, connected: Bool) {
        if connected {
            if let notice = watch.connected(id: device.id, name: device.name, at: clock()), isOn { post(notice) }
        } else {
            watch.disconnected(id: device.id, name: device.name, at: clock())
            DispatchQueue.main.asyncAfter(deadline: .now() + watch.settle + 0.1) { [weak self] in
                MainActor.assumeIsolated { self?.postDue() }
            }
        }
    }

    private func postDue() {
        let due = watch.due(at: clock())
        guard isOn else { return }
        due.forEach(post)
    }

    // MARK: Notification Center

    /// Sends notices to Notification Center, asking for permission once.
    func useNotificationCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        post = { notice in
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

extension ConnectionNotifier: UNUserNotificationCenterDelegate {
    /// Shows the banner even while MacRemote is the frontmost app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onOpen?() }
        }
    }
}
