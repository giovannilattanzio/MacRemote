import Foundation

/// Buttons that do something else while one app is in front, in both modes.
/// Some players ignore the Play/Pause media key (macOS sends it to the
/// "Now Playing" app, or opens Music when there is none), but pause on Space.
public struct AppOverride: Codable, Equatable, Sendable, Identifiable {
    public let bundleID: String
    public var name: String
    /// button key raw value -> action
    public private(set) var actions: [String: RemoteAction]

    public var id: String { bundleID }

    public init(bundleID: String, name: String, actions: [RemoteKey: RemoteAction] = [:]) {
        self.bundleID = bundleID
        self.name = name
        self.actions = Dictionary(uniqueKeysWithValues: actions.map { ($0.key.raw, $0.value) })
    }

    /// The overridden buttons, in remote order.
    public var keys: [RemoteKey] { actions.keys.map(RemoteKey.init(raw:)).sorted() }

    public func action(for key: RemoteKey) -> RemoteAction? { actions[key.raw] }

    public mutating func set(_ action: RemoteAction, for key: RemoteKey) { actions[key.raw] = action }

    public mutating func remove(_ key: RemoteKey) { actions[key.raw] = nil }
}

/// Every app with its own buttons, in the order they were added.
public struct AppOverrides: Codable, Equatable, Sendable {
    public private(set) var apps: [AppOverride]

    public init(apps: [AppOverride] = []) { self.apps = apps }

    /// The app's own action for the button, or nil to use the profile.
    public func action(for key: RemoteKey, app bundleID: String?) -> RemoteAction? {
        guard let bundleID else { return nil }
        return apps.first { $0.bundleID == bundleID }?.action(for: key)
    }

    public func contains(_ bundleID: String) -> Bool { apps.contains { $0.bundleID == bundleID } }

    /// Adds an app with Play/Pause sending Space, the usual reason to add one.
    public mutating func add(bundleID: String, name: String) {
        guard !contains(bundleID) else { return }
        apps.append(AppOverride(bundleID: bundleID, name: name,
                                actions: [RemoteKey(.playPause): .space]))
    }

    public mutating func set(_ action: RemoteAction, for key: RemoteKey, app bundleID: String) {
        guard let index = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[index].set(action, for: key)
    }

    public mutating func remove(_ key: RemoteKey, app bundleID: String) {
        guard let index = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        apps[index].remove(key)
    }

    public mutating func remove(app bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
    }
}
