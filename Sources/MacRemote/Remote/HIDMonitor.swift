import Combine
import Foundation
import IOKit.hid
import os
import MacRemoteKit

/// Finds remotes among the Mac's HID devices and reads their buttons.
/// Fire TV remotes are used automatically; any other keyboard-like device
/// can be turned on in Devices. Devices in use are seized, so their buttons
/// reach only this app and not the system as key presses.
final class HIDMonitor: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String
        var name: String
        var vendorID: Int
        var productID: Int
        var transport: String
        var isFireTV: Bool
        var isEnabled: Bool
        /// Opened, so the app receives its buttons.
        var isOpen = false
        /// Opened exclusively. Otherwise macOS also acts on its keys.
        var isSeized = false
    }

    @Published private(set) var devices: [Device] = []

    /// The name of the first connected remote in use, for status lines.
    var activeRemoteName: String? {
        devices.first { $0.isEnabled && $0.isOpen }?.name
    }
    var onInput: ((HIDUsage, Bool, Device) -> Void)?

    private let defaults: UserDefaults
    private var manager: IOHIDManager?
    /// Every IOHIDDevice (one per top-level collection) under its device id.
    private var refs: [String: [IOHIDDevice]] = [:]
    /// For array-style reports: the usage held on each page of each device.
    private var arrayHeld: [String: HIDUsage] = [:]
    /// Last state of each button of each device. A remote that shows up as
    /// several HID devices reports one press on each; only the first counts.
    private var buttonState: [String: Bool] = [:]
    /// Every raw value from a remote in use, for diagnosing new remotes:
    ///   log stream --level info --predicate 'subsystem == "com.gilattanzio.macremote"'
    private let log = Logger(subsystem: "com.gilattanzio.macremote", category: "hid")

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: Choices people make in Devices

    /// Device ids turned on by hand, and Fire TV remotes turned off by hand.
    private var turnedOn: Set<String> {
        get { Set(defaults.stringArray(forKey: "devices.on") ?? []) }
        set { defaults.set(Array(newValue), forKey: "devices.on") }
    }
    private var turnedOff: Set<String> {
        get { Set(defaults.stringArray(forKey: "devices.off") ?? []) }
        set { defaults.set(Array(newValue), forKey: "devices.off") }
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if devices[index].isFireTV {
            if enabled { turnedOff.remove(id) } else { turnedOff.insert(id) }
        } else {
            if enabled { turnedOn.insert(id) } else { turnedOn.remove(id) }
        }
        devices[index].isEnabled = enabled
        enabled ? open(id) : close(id)
    }

    /// Sample devices for snapshots and the self-test.
    func show(sample: [Device]) { devices = sample }

    // MARK: Discovery

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_SystemControl],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.added(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.removed(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func identity(of device: IOHIDDevice) -> String {
        let vendor = property(device, kIOHIDVendorIDKey) as? Int ?? 0
        let product = property(device, kIOHIDProductIDKey) as? Int ?? 0
        let unique = property(device, kIOHIDPhysicalDeviceUniqueIDKey) as? String
            ?? property(device, kIOHIDSerialNumberKey) as? String
            ?? String(property(device, kIOHIDLocationIDKey) as? Int ?? 0)
        return "\(vendor)-\(product)-\(unique)"
    }

    private func added(_ device: IOHIDDevice) {
        let id = identity(of: device)
        refs[id, default: []].append(device)
        if !devices.contains(where: { $0.id == id }) {
            let vendor = property(device, kIOHIDVendorIDKey) as? Int ?? 0
            let name = property(device, kIOHIDProductKey) as? String ?? "Unknown Device"
            let fireTV = FireTVRemote.isFireTVRemote(vendorID: vendor, product: name)
            devices.append(Device(
                id: id, name: name, vendorID: vendor,
                productID: property(device, kIOHIDProductIDKey) as? Int ?? 0,
                transport: property(device, kIOHIDTransportKey) as? String ?? "",
                isFireTV: fireTV,
                isEnabled: fireTV ? !turnedOff.contains(id) : turnedOn.contains(id)
            ))
            devices.sort { ($0.isFireTV ? 0 : 1, $0.name) < ($1.isFireTV ? 0 : 1, $1.name) }
        }
        if devices.first(where: { $0.id == id })?.isEnabled == true { open(device, id: id) }
    }

    private func removed(_ device: IOHIDDevice) {
        let id = identity(of: device)
        opened.remove(ObjectIdentifier(device))
        seizedRefs.remove(ObjectIdentifier(device))
        refs[id]?.removeAll { $0 === device }
        if refs[id]?.isEmpty ?? true {
            refs[id] = nil
            devices.removeAll { $0.id == id }
            arrayHeld = arrayHeld.filter { !$0.key.hasPrefix(id + "/") }
        } else {
            updateStatus(id)
        }
    }

    // MARK: Opening

    private var opened: Set<ObjectIdentifier> = []
    private var seizedRefs: Set<ObjectIdentifier> = []

    private func open(_ id: String) {
        for device in refs[id] ?? [] { open(device, id: id) }
    }

    private func open(_ device: IOHIDDevice, id: String) {
        guard !opened.contains(ObjectIdentifier(device)) else { return }
        // Exclusive first, so the remote's keys do not also type on the Mac.
        let seized = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
        if !seized {
            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        }
        opened.insert(ObjectIdentifier(device))
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let int = IOHIDValueGetIntegerValue(value)
            let isArray = IOHIDElementGetType(element) == kIOHIDElementTypeInput_Misc
                && IOHIDElementGetReportCount(element) >= 1 && IOHIDElementIsArray(element)
            let device = IOHIDElementGetDevice(element)
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.received(page: page, usage: usage, value: int, isArray: isArray, from: device)
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if seized { seizedRefs.insert(ObjectIdentifier(device)) }
        let page = property(device, kIOHIDPrimaryUsagePageKey) as? Int ?? 0
        let usage = property(device, kIOHIDPrimaryUsageKey) as? Int ?? 0
        log.info("open \(id, privacy: .public) primary=\(String(format: "%02X:%04X", page, usage), privacy: .public) seized=\(seized)")
        updateStatus(id)
    }

    /// One collection that cannot be seized is enough for macOS to act on its keys.
    private func updateStatus(_ id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let open = (refs[id] ?? []).map(ObjectIdentifier.init).filter(opened.contains)
        devices[index].isOpen = !open.isEmpty
        devices[index].isSeized = !open.isEmpty && open.allSatisfy(seizedRefs.contains)
    }

    private func close(_ id: String) {
        for device in refs[id] ?? [] where opened.contains(ObjectIdentifier(device)) {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            opened.remove(ObjectIdentifier(device))
            seizedRefs.remove(ObjectIdentifier(device))
        }
        updateStatus(id)
    }

    // MARK: Input

    private func received(page: UInt32, usage: UInt32, value: Int, isArray: Bool, from device: IOHIDDevice) {
        let id = identity(of: device)
        guard let info = devices.first(where: { $0.id == id }), info.isEnabled else { return }
        log.info("raw \(String(format: "%02X:%04X", page, usage), privacy: .public) value=\(value) array=\(isArray) ref=\(UInt(bitPattern: ObjectIdentifier(device).hashValue))")
        if isArray {
            // Array reports carry the pressed usage as the value, and 0 on release.
            let slot = "\(id)/\(page)"
            if value == 0 {
                if let held = arrayHeld.removeValue(forKey: slot) { emit(held, false, info) }
            } else {
                let pressed = HIDUsage(page: page, usage: UInt32(truncatingIfNeeded: value))
                guard pressed.isButton, arrayHeld[slot] != pressed else { return }
                if let held = arrayHeld[slot] { emit(held, false, info) }
                arrayHeld[slot] = pressed
                emit(pressed, true, info)
            }
            return
        }
        let hid = HIDUsage(page: page, usage: usage)
        guard hid.isButton else { return }
        emit(hid, value != 0, info)
    }

    private func emit(_ usage: HIDUsage, _ pressed: Bool, _ device: Device) {
        let slot = "\(device.id)/\(usage)"
        guard buttonState[slot, default: false] != pressed else { return }
        buttonState[slot] = pressed
        onInput?(usage, pressed, device)
    }
}
