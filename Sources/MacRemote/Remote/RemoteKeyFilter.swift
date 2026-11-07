import AppKit
import CoreGraphics
import os
import MacRemoteKit

/// Drops the events macOS makes from a shared remote's own presses, so the
/// remote does only what MacRemote says. Needed on macOS 12, where the
/// hidutil key block does not hold:
/// - Media keys, always: the remote's Play/Pause otherwise also opens Music.
/// - Keyboard keys, when "Only MacRemote responds to the remote" is on: the
///   D-pad otherwise also sends arrow keys in Pointer mode.
/// The Mac's own keyboard keeps every key. MacRemote's own events carry
/// `marker` and always get through.
///
/// A session event tap. Needs Accessibility. MediaKeyGuard and KeyGuard
/// decide; this class only talks to the event system.
final class RemoteKeyFilter {
    /// Set on every key event MacRemote posts.
    nonisolated static let marker: Int64 = 0x4D52_4D54

    /// A remote in use is open but not seized, so macOS also reads it.
    var remoteShared: () -> Bool = { false }
    /// A remote in use has "Only MacRemote responds" on, so its keys are dropped too.
    var keysBlocked: () -> Bool = { false }
    /// The on-screen keyboard is open: the remote types on it, so its keys are dropped too.
    var keyboardOpen: () -> Bool = { false }

    private var media = MediaKeyGuard()
    private var keys = KeyGuard()
    /// Key events from elsewhere that got through, by key code: for spotting a
    /// remote key that reached macOS before its own report.
    private var passed: [UInt16: TimeInterval] = [:]
    private var tap: CFMachPort?
    private let log = Logger(subsystem: "com.gilattanzio.macremote", category: "keyfilter")

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// The remote's button went down or up.
    func remote(_ usage: HIDUsage, pressed: Bool) {
        let time = now
        media.remote(usage, at: time)
        keys.remote(usage, pressed: pressed, at: time)
        if pressed, keysBlocked() || keyboardOpen(), let code = KeyGuard.keyCode(for: usage),
           let seen = passed[code], time - seen <= KeyGuard.window {
            log.error("key \(code) from the remote reached macOS before its report")
        }
    }

    /// Installs the tap. Call again after Accessibility is granted; it does nothing once running.
    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
            | CGEventMask(1) << CGEventType.keyUp.rawValue
            | CGEventMask(1) << 14 // NX_SYSDEFINED
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let keep = MainActor.assumeIsolated {
                    Unmanaged<RemoteKeyFilter>.fromOpaque(info).takeUnretainedValue().keeps(type, event)
                }
                return keep ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let created else {
            log.error("event tap not created; Accessibility missing?")
            return
        }
        tap = created
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
        log.info("event tap running")
    }

    /// False drops the event.
    private func keeps(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return true }
        switch type {
        case .keyDown, .keyUp: return keepsKey(event)
        default: return keepsMediaKey(event)
        }
    }

    private func keepsKey(_ event: CGEvent) -> Bool {
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let time = now
        let fromRemote = keys.cameFromRemote(code, at: time)
        guard keysBlocked() || keyboardOpen() else {
            if fromRemote { log.info("key \(code) from the remote passed: Only MacRemote responds is off") }
            return true
        }
        if fromRemote {
            log.info("dropped key \(code) from the remote")
            return false
        }
        passed[code] = time
        return true
    }

    private func keepsMediaKey(_ event: CGEvent) -> Bool {
        guard let system = NSEvent(cgEvent: event), system.subtype.rawValue == 8 else { return true }
        let key = Int32((system.data1 & 0xFFFF_0000) >> 16)
        let time = now
        switch media.decide(key, at: time, remoteShared: remoteShared()) {
        case .pass:
            return true
        case .drop:
            log.info("dropped media key \(key) from the remote")
            return false
        case .hold:
            // macOS's copy may arrive before the remote's own report: wait a moment to tell.
            guard let copy = event.copy() else { return true }
            DispatchQueue.main.asyncAfter(deadline: .now() + MediaKeyGuard.holdDelay) { [self] in
                if media.cameFromRemote(key, at: time) {
                    log.info("dropped media key \(key) from the remote (held)")
                } else {
                    copy.setIntegerValueField(.eventSourceUserData, value: Self.marker)
                    copy.post(tap: .cgSessionEventTap)
                }
            }
            return false
        }
    }
}
