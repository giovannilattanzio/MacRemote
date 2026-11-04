import Foundation

/// The remote works in one mode at a time. Menu switches between them.
public enum RemoteMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The D-pad sends arrow keys, Select sends Return: menus, lists, players.
    case navigation
    /// The D-pad moves the pointer, Select clicks: anything else.
    case pointer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .navigation: "Navigation"
        case .pointer: "Pointer"
        }
    }

    public var symbol: String {
        switch self {
        case .navigation: "arrow.up.and.down.and.arrow.left.and.right"
        case .pointer: "cursorarrow.motionlines"
        }
    }

    public var next: RemoteMode { self == .navigation ? .pointer : .navigation }
}

/// Which action each button does in each mode.
public struct Profile: Codable, Equatable, Sendable {
    /// mode raw value -> button key raw value -> action
    private var bindings: [String: [String: RemoteAction]]

    public init(bindings: [RemoteMode: [RemoteKey: RemoteAction]] = [:]) {
        self.bindings = [:]
        for (mode, table) in bindings {
            for (key, action) in table { set(action, for: key, in: mode) }
        }
    }

    public func action(for key: RemoteKey, in mode: RemoteMode) -> RemoteAction {
        bindings[mode.rawValue]?[key.raw] ?? .none
    }

    public mutating func set(_ action: RemoteAction, for key: RemoteKey, in mode: RemoteMode) {
        bindings[mode.rawValue, default: [:]][key.raw] = action
    }

    /// Every button with a binding in any mode, plus every known button, in remote order.
    public var keys: [RemoteKey] {
        var all = Set(RemoteButton.allCases.map(RemoteKey.init))
        for table in bindings.values { for raw in table.keys { all.insert(RemoteKey(raw: raw)) } }
        return all.sorted()
    }

    /// Adds a button the app learned from a remote, so it shows in the list.
    public mutating func learn(_ key: RemoteKey) {
        for mode in RemoteMode.allCases where bindings[mode.rawValue]?[key.raw] == nil {
            set(.none, for: key, in: mode)
        }
    }

    public static let standard: Profile = {
        let shared: [RemoteButton: RemoteAction] = [
            .menu: .toggleMode,
            .playPause: .playPause,
            .volumeUp: .volumeUp,
            .volumeDown: .volumeDown,
            .mute: .mute,
            .voice: .spotlight,
            .guide: .switchApp,
        ]
        var navigation: [RemoteButton: RemoteAction] = [
            .up: .arrowUp, .down: .arrowDown, .left: .arrowLeft, .right: .arrowRight,
            .select: .returnKey, .back: .escape, .home: .missionControl,
            .rewind: .previousTrack, .fastForward: .nextTrack,
        ]
        var pointer: [RemoteButton: RemoteAction] = [
            .up: .pointerUp, .down: .pointerDown, .left: .pointerLeft, .right: .pointerRight,
            .select: .leftClick, .back: .escape, .home: .rightClick,
            .rewind: .scrollUp, .fastForward: .scrollDown,
        ]
        navigation.merge(shared) { own, _ in own }
        pointer.merge(shared) { own, _ in own }
        func keyed(_ table: [RemoteButton: RemoteAction]) -> [RemoteKey: RemoteAction] {
            Dictionary(uniqueKeysWithValues: table.map { (RemoteKey($0.key), $0.value) })
        }
        return Profile(bindings: [.navigation: keyed(navigation), .pointer: keyed(pointer)])
    }()
}
