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
        /// macOS told to ignore its keys (KeyBlock), because it could not be seized.
        var keysBlocked = false
        /// The charge, when the remote or macOS reports it.
        var battery: Battery?

        /// Only MacRemote acts on its presses.
        var isExclusive: Bool { isSeized || keysBlocked }
    }

    @Published private(set) var devices: [Device] = []

    /// The name of the first connected remote in use, for status lines.
    var activeRemoteName: String? { activeRemote?.name }

    /// The first connected remote in use.
    var activeRemote: Device? {
        devices.first { $0.isEnabled && $0.isOpen }
    }
    var onInput: ((HIDUsage, Bool, Device) -> Void)?
    /// A remote in use appeared (true) or went away (false).
    var onConnection: ((Device, Bool) -> Void)?

    private let defaults: UserDefaults
    private var manager: IOHIDManager?
    /// Every IOHIDDevice (one per top-level collection) under its device id.
    private var refs: [String: [IOHIDDevice]] = [:]
    /// For array-style reports: the usage held on each page of each device.
    private var arrayHeld: [String: HIDUsage] = [:]
    /// Last state of each button of each device. A remote that shows up as
    /// several HID devices reports one press on each; only the first counts.
    private var buttonState: [String: Bool] = [:]
    /// The one IOHIDDevice per device id whose reports count. macOS lists a
    /// Fire TV remote twice, and the copies do not always arrive interleaved.
    private var owner: [String: ObjectIdentifier] = [:]
    /// Every raw value from a remote in use, for diagnosing new remotes:
    ///   log stream --level info --predicate 'subsystem == "com.gilattanzio.macremote"'
    private let log = Logger(subsystem: "com.gilattanzio.macremote", category: "hid")

    init(defaults: UserDefaults) {
        self.defaults = defaults
        blockKeys = defaults.bool(forKey: "devices.blockKeys")
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

    /// "Only MacRemote responds to the remote", from the Devices page.
    @Published var blockKeys: Bool {
        didSet {
            defaults.set(blockKeys, forKey: "devices.blockKeys")
            applyBlocking()
        }
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
        // macOS updates BatteryPercent on its own schedule; a minute is plenty for a remote.
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBatteries() }
        }
    }

    // MARK: Battery

    private var batteryTimer: Timer?

    private func refreshBatteries() {
        for device in devices { readBattery(device.id) }
        for (id, list) in refs {
            for device in list where opened.contains(ObjectIdentifier(device)) { requestBattery(device, id: id) }
        }
    }

    /// Asks the remote for its Battery Strength element, for remotes on
    /// classic Bluetooth, where macOS does not keep a BatteryPercent.
    /// Done off the main thread: the request goes to the remote and waits.
    private func requestBattery(_ device: IOHIDDevice, id: String) {
        let matching = [kIOHIDElementUsagePageKey: Int(Battery.usagePage), kIOHIDElementUsageKey: Int(Battery.usage)]
        guard let element = (IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, 0) as? [IOHIDElement])?.first
        else { return }
        let request = BatteryRequest(device: device, element: element)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let reading = request.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(batteryReading: reading, for: id) }
            }
        }
    }

    private func received(batteryReading reading: BatteryRequest.Reading, for id: String) {
        log.notice("battery read \(id, privacy: .public) result=\(String(format: "0x%x", reading.result), privacy: .public) raw=\(reading.raw) range=\(reading.min)...\(reading.max)")
        let isFireTV = devices.first { $0.id == id }?.isFireTV ?? false
        guard reading.result == kIOReturnSuccess,
              let battery = Battery(raw: reading.raw, logicalMin: reading.min, logicalMax: reading.max,
                                    isPercent: isFireTV) else { return }
        setBattery(battery, for: id)
    }

    /// Reads BatteryPercent from the device's registry entry or the
    /// Bluetooth entries above it, where macOS puts it for LE remotes.
    private func readBattery(_ id: String) {
        for device in refs[id] ?? [] {
            let service = IOHIDDeviceGetService(device)
            guard service != MACH_PORT_NULL else { continue }
            let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, Battery.registryKey as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            if let battery = Battery(registryValue: value) {
                setBattery(battery, for: id)
                return
            }
        }
    }

    private func setBattery(_ battery: Battery, for id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }),
              devices[index].battery != battery else { return }
        devices[index].battery = battery
        log.notice("battery \(id, privacy: .public) \(battery.percent)%")
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
            if let device = devices.first(where: { $0.id == id }), device.isEnabled { onConnection?(device, true) }
        }
        if devices.first(where: { $0.id == id })?.isEnabled == true { open(device, id: id) }
        readBattery(id)
    }

    private func removed(_ device: IOHIDDevice) {
        let id = identity(of: device)
        opened.remove(ObjectIdentifier(device))
        seizedRefs.remove(ObjectIdentifier(device))
        if owner[id] == ObjectIdentifier(device) { owner[id] = nil }
        refs[id]?.removeAll { $0 === device }
        if refs[id]?.isEmpty ?? true {
            refs[id] = nil
            if let device = devices.first(where: { $0.id == id }), device.isEnabled { onConnection?(device, false) }
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
            let range = (IOHIDElementGetLogicalMin(element), IOHIDElementGetLogicalMax(element))
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.received(page: page, usage: usage, value: int, range: range, isArray: isArray, from: device)
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if seized { seizedRefs.insert(ObjectIdentifier(device)) }
        let page = property(device, kIOHIDPrimaryUsagePageKey) as? Int ?? 0
        let usage = property(device, kIOHIDPrimaryUsageKey) as? Int ?? 0
        log.info("open \(id, privacy: .public) primary=\(String(format: "%02X:%04X", page, usage), privacy: .public) seized=\(seized)")
        updateStatus(id)
        requestBattery(device, id: id)
    }

    /// One collection that cannot be seized is enough for macOS to act on its keys.
    private func updateStatus(_ id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let open = (refs[id] ?? []).map(ObjectIdentifier.init).filter(opened.contains)
        devices[index].isOpen = !open.isEmpty
        devices[index].isSeized = !open.isEmpty && open.allSatisfy(seizedRefs.contains)
        applyBlocking()
    }

    // MARK: Key blocking

    /// Blocks or unblocks each device's keys in macOS to match the setting:
    /// blocked while the device is in use and could not be seized.
    private func applyBlocking() {
        for index in devices.indices {
            let device = devices[index]
            let wanted = blockKeys && device.isEnabled && device.isOpen && !device.isSeized
            guard wanted != device.keysBlocked else { continue }
            if setKeyBlock(wanted, vendorID: device.vendorID, productID: device.productID) {
                devices[index].keysBlocked = wanted
            }
        }
    }

    /// Gives every blocked remote its keys back. Called when the app quits,
    /// so a remote never stays silent without MacRemote running.
    func clearBlocking() {
        for index in devices.indices where devices[index].keysBlocked {
            _ = setKeyBlock(false, vendorID: devices[index].vendorID, productID: devices[index].productID)
            devices[index].keysBlocked = false
        }
    }

    private func setKeyBlock(_ blocked: Bool, vendorID: Int, productID: Int) -> Bool {
        guard !Store.isOverridden else { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property",
                             "--matching", KeyBlock.matching(vendorID: vendorID, productID: productID),
                             "--set", KeyBlock.setting(blocked: blocked)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("hidutil failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        log.info("keys \(blocked ? "blocked" : "restored", privacy: .public) for \(vendorID):\(productID) exit=\(process.terminationStatus)")
        return process.terminationStatus == 0
    }

    private func close(_ id: String) {
        for device in refs[id] ?? [] where opened.contains(ObjectIdentifier(device)) {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            opened.remove(ObjectIdentifier(device))
            seizedRefs.remove(ObjectIdentifier(device))
        }
        owner[id] = nil
        updateStatus(id)
    }

    // MARK: Input

    private func received(page: UInt32, usage: UInt32, value: Int, range: (Int, Int), isArray: Bool, from device: IOHIDDevice) {
        let id = identity(of: device)
        guard let info = devices.first(where: { $0.id == id }), info.isEnabled else { return }
        log.info("raw \(String(format: "%02X:%04X", page, usage), privacy: .public) value=\(value) array=\(isArray) ref=\(UInt(bitPattern: ObjectIdentifier(device).hashValue))")
        let ref = ObjectIdentifier(device)
        if owner[id] == nil { owner[id] = ref }
        guard owner[id] == ref else { return }
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
        if page == Battery.usagePage && usage == Battery.usage {
            log.notice("battery report \(id, privacy: .public) raw=\(value) range=\(range.0)...\(range.1)")
            if let battery = Battery(raw: value, logicalMin: range.0, logicalMax: range.1, isPercent: info.isFireTV) {
                setBattery(battery, for: id)
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

/// One Battery Strength read, safe to run off the main thread: IOHIDDevice
/// calls are thread-safe, and the device stays retained until it finishes.
nonisolated private struct BatteryRequest: @unchecked Sendable {
    struct Reading: Sendable {
        var result: IOReturn
        var raw: Int
        var min: Int
        var max: Int
    }

    let device: IOHIDDevice
    let element: IOHIDElement

    /// kIOHIDDeviceGetValueWithUpdate (IOHIDDevice.h), which Swift does not import:
    /// sends a get-report to the device instead of returning the last value.
    private static let withUpdate: IOOptionBits = 0x0002_0000

    func read() -> Reading {
        // The out value follows the Get rule: the element owns it, so it must
        // not be released here. The placeholder only gives `value` a start.
        let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
        var value = Unmanaged.passUnretained(placeholder)
        let result = withExtendedLifetime(placeholder) {
            IOHIDDeviceGetValueWithOptions(device, element, &value, Self.withUpdate)
        }
        // takeUnretainedValue retains it for as long as Swift uses it.
        let raw = result == kIOReturnSuccess ? IOHIDValueGetIntegerValue(value.takeUnretainedValue()) : 0
        return Reading(result: result, raw: raw,
                       min: IOHIDElementGetLogicalMin(element), max: IOHIDElementGetLogicalMax(element))
    }
}
