import AppKit
import MacRemoteKit

/// Self-test for agents: drives the real engine with simulated remote
/// presses into a recording sink, prints PASS or FAIL per check, and quits
/// with exit code 0 or 1. Nothing reaches the real Mac.
///   APP_STORE=/tmp/MacRemote-self /Applications/MacRemote.app/Contents/MacOS/MacRemote --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    final class Recorder: EffectSink {
        var log: [String] = []
        var moved = (dx: 0.0, dy: 0.0)
        var scrolled = 0.0
        func begin(_ action: RemoteAction) { log.append("+\(action.rawValue)") }
        func end(_ action: RemoteAction) { log.append("-\(action.rawValue)") }
        func movePointer(dx: Double, dy: Double) { moved.dx += dx; moved.dy += dy }
        func scroll(dx: Double, dy: Double) { scrolled += dy }
    }

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE")
            finish(code: 1)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            let recorder = Recorder()
            let engine = RemoteEngine(defaults: Store.defaults, sink: recorder)
            var now = 100.0
            engine.clock = { now }
            @MainActor func press(_ usage: HIDUsage, exclusive: Bool = true) {
                engine.handle(usage: usage, pressed: true, exclusive: exclusive, from: "Test Remote")
            }
            @MainActor func release(_ usage: HIDUsage) {
                engine.handle(usage: usage, pressed: false, exclusive: true, from: "Test Remote")
            }
            @MainActor func advance(_ seconds: Double) {
                let steps = Int(seconds * 100)
                for _ in 0..<steps { now += 0.01; engine.tick() }
            }

            press(.key(0x28)); release(.key(0x28))
            check("Select presses Return in Navigation mode", recorder.log == ["+returnKey", "-returnKey"])
            check("presses show in the recent list", engine.recent.first?.action == .returnKey)

            recorder.log = []
            press(.key(0x50)); advance(0.75); release(.key(0x50))
            let lefts = recorder.log.filter { $0 == "+arrowLeft" }.count
            check("holding Left repeats the arrow key", lefts >= 4, "\(lefts) presses")

            recorder.log = []
            press(.key(0x52), exclusive: false); release(.key(0x52))
            check("a shared remote does not press Up twice", recorder.log.isEmpty)

            press(.consumer(0x40)); press(.consumer(0x40)); release(.consumer(0x40)); release(.consumer(0x40))
            check("Menu switches to Pointer mode, even when the press is reported twice", engine.mode == .pointer)

            press(.key(0x4F)); advance(0.5); release(.key(0x4F))
            check("holding Right moves the pointer right", recorder.moved.dx > 40 && recorder.moved.dy == 0,
                  "moved \(recorder.moved)")

            recorder.log = []
            press(.key(0x28)); press(.key(0x51)); advance(0.2); release(.key(0x51)); release(.key(0x28))
            check("holding Select while moving drags", recorder.log.filter { $0.hasSuffix("Click") } == ["+leftClick", "-leftClick"] && recorder.moved.dy > 0, "\(recorder.log) \(recorder.moved)")

            press(.consumer(0xB3)); advance(0.3); release(.consumer(0xB3))
            check("Fast Forward scrolls down in Pointer mode", recorder.scrolled < 0)

            engine.isEnabled = false
            recorder.log = []
            press(.key(0x28)); release(.key(0x28))
            check("a paused remote does nothing", recorder.log.isEmpty)
            engine.isEnabled = true

            let learned = HIDUsage.consumer(0x1A0)
            press(learned); release(learned)
            check("an unknown button is learned", engine.profile.keys.contains(RemoteKey(usage: learned)))
            engine.profile.set(.fullScreen, for: RemoteKey(usage: learned), in: .pointer)
            recorder.log = []
            press(learned); release(learned)
            check("a learned button runs its action", recorder.log.first == "+fullScreen")

            recorder.log = []
            engine.setMode(.navigation)
            press(.key(0x52), exclusive: true); release(.key(0x52))
            check("with macOS ignoring the remote's keys, the app presses Up itself", recorder.log.first == "+arrowUp")

            let reloaded = RemoteEngine(defaults: Store.defaults, sink: recorder)
            check("button choices are saved", reloaded.profile == engine.profile)
            engine.restoreDefaults()
            check("Restore Defaults resets buttons", engine.profile == .standard)

            var notices: [RemoteNotice] = []
            var uptime = 0.0
            let notifier = RemoteNotifier(defaults: Store.defaults, settle: 0.1, startQuiet: 1, clock: { uptime })
            notifier.post = { notices.append($0) }
            let remote = HIDMonitor.Device(id: "r", name: "Test Remote", vendorID: 0x1949, productID: 1,
                                           transport: "Bluetooth", isFireTV: true, isEnabled: true)
            notifier.connection(remote, connected: true)
            check("a remote already connected at launch does not notify", notices.isEmpty)
            uptime = 5
            notifier.connection(remote, connected: true)
            check("connecting a remote notifies", notices == [RemoteNotice(.connected, name: "Test Remote")])
            notices = []
            notifier.connection(remote, connected: false)
            notifier.connection(remote, connected: true)
            uptime = 6
            try? await Task.sleep(nanoseconds: 300_000_000)
            check("a remote that drops and comes right back does not notify", notices.isEmpty, "\(notices)")
            notifier.connection(remote, connected: false)
            uptime = 7
            try? await Task.sleep(nanoseconds: 300_000_000)
            check("disconnecting a remote notifies", notices == [RemoteNotice(.disconnected, name: "Test Remote")], "\(notices)")
            notices = []
            Store.defaults.set(false, forKey: RemoteNotifier.settingKey)
            notifier.connection(remote, connected: true)
            check("with notifications off, nothing is posted", notices.isEmpty)
            Store.defaults.removeObject(forKey: RemoteNotifier.settingKey)

            var low = remote
            low.battery = Battery(percent: 15)
            notifier.battery(low)
            check("a low battery notifies", notices == [RemoteNotice(.lowBattery(15), name: "Test Remote")], "\(notices)")
            notices = []
            low.battery = Battery(percent: 12)
            notifier.battery(low)
            check("a battery already reported low does not notify again", notices.isEmpty, "\(notices)")
            low.battery = Battery(percent: 100)
            notifier.battery(low)
            Store.defaults.set(false, forKey: RemoteNotifier.batterySettingKey)
            low.battery = Battery(percent: 10)
            notifier.battery(low)
            check("with low battery notifications off, nothing is posted", notices.isEmpty, "\(notices)")
            Store.defaults.removeObject(forKey: RemoteNotifier.batterySettingKey)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
