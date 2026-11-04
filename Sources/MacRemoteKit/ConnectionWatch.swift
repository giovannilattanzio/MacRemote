import Foundation

/// A notification about a remote: it came, went, or its battery is low.
public struct RemoteNotice: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case connected, disconnected
        /// The charge left, in percent.
        case lowBattery(Int)
    }

    public let kind: Kind
    public let name: String

    public init(_ kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }

    public var title: String {
        switch kind {
        case .connected: "\(name) Connected"
        case .disconnected: "\(name) Disconnected"
        case .lowBattery: "\(name) Battery Low"
        }
    }

    public var body: String {
        switch kind {
        case .connected: "The remote is ready to control your Mac."
        case .disconnected: "Press a button on the remote to reconnect it."
        case .lowBattery(let percent): "\(percent)% left. Replace the remote's batteries soon."
        }
    }
}

/// Decides which connects and disconnects are worth a notification.
/// Remotes already connected when the app starts stay quiet, and a remote
/// that drops and comes back within `settle` seconds (Bluetooth does this,
/// and macOS lists a Fire TV remote as several devices) stays quiet too.
/// Times are seconds on any steady clock.
public struct ConnectionWatch: Sendable {
    /// How long after start connects are the remotes already there.
    public var startQuiet: TimeInterval
    /// How long a disconnect waits for the remote to come back.
    public var settle: TimeInterval

    private let start: TimeInterval
    private var pending: [String: (name: String, at: TimeInterval)] = [:]

    public init(start: TimeInterval, startQuiet: TimeInterval = 3, settle: TimeInterval = 3) {
        self.start = start
        self.startQuiet = startQuiet
        self.settle = settle
    }

    /// A remote connected. Returns the notice to show, if any.
    public mutating func connected(id: String, name: String, at now: TimeInterval) -> RemoteNotice? {
        if pending.removeValue(forKey: id) != nil { return nil }
        guard now - start >= startQuiet else { return nil }
        return RemoteNotice(.connected, name: name)
    }

    /// A remote disconnected. Its notice waits `settle` seconds; collect it with `due(at:)`.
    public mutating func disconnected(id: String, name: String, at now: TimeInterval) {
        pending[id] = (name, now)
    }

    /// Disconnects that stayed disconnected for `settle` seconds, oldest first.
    public mutating func due(at now: TimeInterval) -> [RemoteNotice] {
        let ready = pending.filter { now - $0.value.at >= settle }.sorted { $0.value.at < $1.value.at }
        for (id, _) in ready { pending[id] = nil }
        return ready.map { RemoteNotice(.disconnected, name: $0.value.name) }
    }
}
