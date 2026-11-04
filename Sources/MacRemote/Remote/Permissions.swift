import AppKit
import ApplicationServices
import IOKit.hid

/// The two permissions the app needs:
/// - Input Monitoring, to read the remote's buttons.
/// - Accessibility, to press keys and move the pointer.
/// macOS gives no notice when one is granted, so the app checks every two
/// seconds until both are on.
@Observable
final class Permissions {
    private(set) var inputMonitoring = false
    private(set) var accessibility = false
    var onChange: (() -> Void)?
    private var timer: Timer?

    var allGranted: Bool { inputMonitoring && accessibility }

    func refresh() {
        let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        let access = AXIsProcessTrusted()
        let changed = input != inputMonitoring || access != accessibility
        inputMonitoring = input
        accessibility = access
        if changed { onChange?() }
        if allGranted {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { AppModel.shared.permissions.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            open("Privacy_ListenEvent")
        }
        refresh()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            open("Privacy_Accessibility")
        }
        refresh()
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
