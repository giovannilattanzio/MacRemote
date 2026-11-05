import AppKit
import Combine
import Foundation
import os
import MacRemoteKit

/// Turns remote button presses into actions on the Mac: looks up the action
/// for the button in the current mode, then runs it once, repeats it like a
/// held key, or keeps moving the pointer while the button is down.
final class RemoteEngine: ObservableObject {
    struct Press: Identifiable, Equatable {
        let id = UUID()
        let key: RemoteKey
        let usage: HIDUsage
        let action: RemoteAction
        let device: String
        let date: Date
        /// macOS already did it, because the remote could not be used exclusively.
        let handledByMac: Bool
    }

    @Published var profile: Profile { didSet { save() } }
    /// Buttons that do something else while a chosen app is in front.
    @Published var appOverrides: AppOverrides { didSet { saveOverrides() } }
    @Published private(set) var mode: RemoteMode = .navigation
    @Published var isEnabled = true {
        didSet { if !isEnabled { releaseAll() } }
    }
    /// The newest first, at most 12.
    @Published private(set) var recent: [Press] = []
    /// Buttons held down right now, to light up the remote picture.
    @Published private(set) var lit: Set<RemoteButton> = []
    /// Every button pressed since launch. A TV control here means the remote has them.
    @Published private(set) var seen: Set<RemoteButton> = []
    var onModeChange: ((RemoteMode) -> Void)?

    /// 0 slow ... 1 fast, from Settings.
    var pointerSpeed: Double { defaults.object(forKey: "pointerSpeed") as? Double ?? 0.5 }
    var scrollSpeed: Double { defaults.object(forKey: "scrollSpeed") as? Double ?? 0.5 }

    private let defaults: UserDefaults
    private let sink: EffectSink
    private let repeatTiming = KeyRepeat()
    private let log = Logger(subsystem: "com.gilattanzio.macremote", category: "engine")

    private struct Held {
        let action: RemoteAction
        let start: TimeInterval
        var fired: Int
        /// False when macOS performs the action itself.
        let perform: Bool
    }
    private var held: [RemoteKey: Held] = [:]
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    /// Injected by the self-test, so time moves on demand.
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// The bundle ID of the app in front. Injected by the self-test.
    var frontmostApp: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    init(defaults: UserDefaults, sink: EffectSink) {
        self.defaults = defaults
        self.sink = sink
        if let data = defaults.data(forKey: "profile"),
           let saved = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = saved
        } else {
            profile = .standard
        }
        if let data = defaults.data(forKey: "appOverrides"),
           let saved = try? JSONDecoder().decode(AppOverrides.self, from: data) {
            appOverrides = saved
        } else {
            appOverrides = AppOverrides()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: "profile") }
    }

    private func saveOverrides() {
        if let data = try? JSONEncoder().encode(appOverrides) { defaults.set(data, forKey: "appOverrides") }
    }

    func restoreDefaults() { profile = .standard }

    func toggleMode() { setMode(mode.next) }

    func setMode(_ new: RemoteMode) {
        guard new != mode else { return }
        releaseAll()
        mode = new
        onModeChange?(new)
    }

    // MARK: Input

    /// - exclusive: the remote is seized, so nothing reached macOS but this app.
    func handle(usage: HIDUsage, pressed: Bool, exclusive: Bool, from device: String) {
        let key = RemoteKey(usage: usage)
        if key.button == nil, !profile.keys.contains(key) { profile.learn(key) }
        if let button = key.button {
            if pressed {
                lit.insert(button)
                if !seen.contains(button) { seen.insert(button) }
            } else {
                lit.remove(button)
            }
        }
        if pressed { press(key, usage: usage, exclusive: exclusive, device: device) } else { release(key) }
    }

    private func press(_ key: RemoteKey, usage: HIDUsage, exclusive: Bool, device: String) {
        guard isEnabled, held[key] == nil else { return }
        let action = appOverrides.action(for: key, app: frontmostApp()) ?? profile.action(for: key, in: mode)
        let byMac = !exclusive && RemoteAction.native(for: usage) == action
        recent.insert(Press(key: key, usage: usage, action: action, device: device,
                            date: .now, handledByMac: byMac), at: 0)
        if recent.count > 12 { recent.removeLast() }
        log.info("press \(key.raw, privacy: .public) mode=\(self.mode.rawValue, privacy: .public) action=\(action.rawValue, privacy: .public) byMac=\(byMac)")
        guard action != .none else { return }
        if action == .toggleMode {
            toggleMode()
            // Held like any button, so a repeated report of the same press does not switch back.
            held[key] = Held(action: action, start: clock(), fired: 1, perform: false)
            return
        }
        let now = clock()
        held[key] = Held(action: action, start: now, fired: 1, perform: !byMac)
        if !byMac { sink.begin(action) }
        if action.hold != .once { startTimer() }
    }

    private func release(_ key: RemoteKey) {
        guard let entry = held.removeValue(forKey: key) else { return }
        if entry.perform { sink.end(entry.action) }
        if held.isEmpty { stopTimer() }
    }

    private func releaseAll() {
        for key in held.keys { release(key) }
    }

    // MARK: Holding

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = clock()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.engine.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Runs held buttons forward to now. The timer calls it; the self-test calls it directly.
    func tick() {
        let now = clock()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        let motion = PointerMotion(sliderValue: pointerSpeed)
        let scrollRate = 300 + 1500 * scrollSpeed
        var move = (dx: 0.0, dy: 0.0)
        var scroll = (dx: 0.0, dy: 0.0)
        for (key, var entry) in held where entry.perform {
            let heldFor = now - entry.start
            switch entry.action.effect {
            case .move(let dx, let dy):
                let distance = motion.speed(heldFor: heldFor) * dt
                move.dx += dx * distance
                move.dy += dy * distance
            case .scroll(let dx, let dy):
                scroll.dx += dx * scrollRate * dt
                scroll.dy += dy * scrollRate * dt
            default:
                guard entry.action.hold == .repeats else { continue }
                let due = repeatTiming.presses(heldFor: heldFor)
                while entry.fired < due {
                    sink.begin(entry.action)
                    sink.end(entry.action)
                    entry.fired += 1
                }
                held[key] = entry
            }
        }
        // Holding two directions moves diagonally at the same speed as one.
        if move.dx != 0, move.dy != 0 {
            move.dx /= 2.squareRoot()
            move.dy /= 2.squareRoot()
        }
        if move.dx != 0 || move.dy != 0 { sink.movePointer(dx: move.dx, dy: move.dy) }
        if scroll.dx != 0 || scroll.dy != 0 { sink.scroll(dx: scroll.dx, dy: scroll.dy) }
    }

    /// Sample presses for snapshots.
    func show(lit sampleLit: Set<RemoteButton> = [], sample: [Press]) {
        recent = sample
        lit = sampleLit
    }
}
