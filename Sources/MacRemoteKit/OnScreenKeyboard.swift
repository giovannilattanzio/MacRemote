import Foundation

/// One key of the on-screen keyboard.
public struct KeyboardKey: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case character(String)
        case shift, layer, space, delete, returnKey, hide
    }

    public let kind: Kind
    /// In key units: a letter key is 1.
    public let width: Int
    public var id: String {
        switch kind {
        case .character(let text): "char:\(text)"
        case .shift: "shift"
        case .layer: "layer"
        case .space: "space"
        case .delete: "delete"
        case .returnKey: "return"
        case .hide: "hide"
        }
    }

    public init(_ kind: Kind, width: Int = 1) {
        self.kind = kind
        self.width = width
    }
}

/// The keyboard the remote types on: a highlighted key that the D-pad moves
/// and Select presses. Two layers (letters, and numbers with symbols), a
/// Shift that lasts one letter, or stays on when pressed twice.
public struct OnScreenKeyboard: Equatable, Sendable {
    public enum Layer: Sendable { case letters, symbols }
    public enum ShiftState: Sendable { case off, once, locked }
    public enum Direction: Sendable { case up, down, left, right }

    /// What pressing a key sends to the app in front.
    public enum Output: Equatable, Sendable {
        case text(String), delete, returnKey, hide
    }

    /// Every row is this many key units wide.
    public static let rowUnits = 12

    public private(set) var layer: Layer = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var row = 0
    public private(set) var column = 0
    /// Where moving up or down aims, in key units from the left edge, so
    /// passing over the wide Space bar comes back to the same column.
    private var aim: Double = 0.5

    public init() {}

    public var rows: [[KeyboardKey]] { layer == .letters ? Self.letters : Self.symbols }
    public var focused: KeyboardKey { rows[row][column] }

    /// The text a key shows, with Shift applied.
    public func label(for key: KeyboardKey) -> String {
        switch key.kind {
        case .character(let text): shift == .off ? text : text.uppercased()
        case .shift: "shift"
        case .layer: layer == .letters ? "123" : "ABC"
        case .space: "space"
        case .delete: "delete"
        case .returnKey: "return"
        case .hide: "hide"
        }
    }

    /// Back to the first key of the letters, Shift off. Called when it opens.
    public mutating func reset() {
        self = OnScreenKeyboard()
    }

    public mutating func move(_ direction: Direction) {
        let keys = rows[row]
        switch direction {
        case .left:
            column = (column + keys.count - 1) % keys.count
            aim = center(row, column)
        case .right:
            column = (column + 1) % keys.count
            aim = center(row, column)
        case .up:
            row = (row + rows.count - 1) % rows.count
            column = key(at: aim, in: row)
        case .down:
            row = (row + 1) % rows.count
            column = key(at: aim, in: row)
        }
    }

    /// Presses the highlighted key. Shift and the layer key change the
    /// keyboard and send nothing.
    public mutating func press() -> Output? {
        switch focused.kind {
        case .character(let text):
            let typed = shift == .off ? text : text.uppercased()
            if shift == .once { shift = .off }
            return .text(typed)
        case .shift:
            shift = switch shift {
            case .off: .once
            case .once: .locked
            case .locked: .off
            }
            return nil
        case .layer:
            layer = layer == .letters ? .symbols : .letters
            shift = .off
            row = min(row, rows.count - 1)
            column = key(at: aim, in: row)
            return nil
        case .space: return .text(" ")
        case .delete: return .delete
        case .returnKey: return .returnKey
        case .hide: return .hide
        }
    }

    // MARK: Layout

    private func center(_ row: Int, _ column: Int) -> Double {
        let keys = rows[row]
        let left = keys[..<column].reduce(0) { $0 + $1.width }
        return Double(left) + Double(keys[column].width) / 2
    }

    /// The key under a point of a row, in key units.
    private func key(at x: Double, in row: Int) -> Int {
        var left = 0
        for (index, key) in rows[row].enumerated() {
            if x < Double(left + key.width) { return index }
            left += key.width
        }
        return rows[row].count - 1
    }

    private static func chars(_ text: String) -> [KeyboardKey] {
        text.map { KeyboardKey(.character(String($0))) }
    }

    private static let bottomRow = [
        KeyboardKey(.layer, width: 2), KeyboardKey(.space, width: 8), KeyboardKey(.hide, width: 2),
    ]

    static let letters: [[KeyboardKey]] = [
        chars("qwertyuiop") + [KeyboardKey(.delete, width: 2)],
        chars("asdfghjkl@") + [KeyboardKey(.returnKey, width: 2)],
        [KeyboardKey(.shift, width: 2)] + chars("zxcvbnm,.-"),
        bottomRow,
    ]

    static let symbols: [[KeyboardKey]] = [
        chars("1234567890") + [KeyboardKey(.delete, width: 2)],
        chars("-/:;()$&\"'") + [KeyboardKey(.returnKey, width: 2)],
        chars(".,?!_+=#%*~\\"),
        bottomRow,
    ]
}

/// What each remote button does while the keyboard is open, told to the
/// keyboard as the action that button would press on a real keyboard.
/// Buttons not listed (volume, Play/Pause, Menu) keep their own actions.
public enum KeyboardButtons {
    public static func action(for button: RemoteButton) -> RemoteAction? {
        switch button {
        case .up: .arrowUp
        case .down: .arrowDown
        case .left: .arrowLeft
        case .right: .arrowRight
        case .select: .returnKey
        case .back: .escape
        case .rewind: .delete
        case .fastForward: .space
        default: nil
        }
    }
}

/// Decides when the on-screen keyboard opens and closes by itself. It opens
/// when the remote moves focus into a text field, or clicks one, and closes
/// when focus leaves text fields. A field focused by the Mac's own keyboard
/// or mouse, or one already focused when the remote is used, leaves it shut.
///
/// The app tells it about each remote press and asks it about the focused
/// element a few times a second while it watches. `Element` is the focused
/// element (an AXUIElement in the app).
public struct KeyboardTrigger<Element: Equatable> {
    public enum Decision: Equatable, Sendable { case none, show, hide }

    /// How long after a remote press a new focus counts as the remote's.
    public static var watchTime: TimeInterval { 4 }
    /// How long after a click a text field that already had focus counts as clicked.
    public static var clickTime: TimeInterval { 1 }
    /// Observations without a text field in a row before it closes, so a
    /// suggestion list that takes focus for a moment does not close it.
    public static var leaveCount: Int { 2 }

    private var last: Element?
    private var watchUntil: TimeInterval = -.infinity
    private var clickUntil: TimeInterval = -.infinity
    private var away = 0

    public init() {}

    public func isWatching(at time: TimeInterval) -> Bool { time <= watchUntil }

    /// The remote pressed a button. `focus` is the focused element before the
    /// press does anything; it is only read when not already watching.
    public mutating func remotePressed(click: Bool, at time: TimeInterval, focus: () -> Element?) {
        if !isWatching(at: time) { last = focus() }
        watchUntil = time + Self.watchTime
        if click { clickUntil = time + Self.clickTime }
    }

    /// - showing: the keyboard is open because a text field got focus.
    public mutating func observe(focus: Element?, isText: Bool, showing: Bool, at time: TimeInterval) -> Decision {
        defer { last = focus }
        if showing {
            away = isText ? 0 : away + 1
            return away >= Self.leaveCount ? .hide : .none
        }
        away = 0
        guard isText, isWatching(at: time) else { return .none }
        if focus != last || time <= clickUntil {
            clickUntil = -.infinity
            return .show
        }
        return .none
    }

    /// The keyboard closed, by the remote or by focus leaving. Focus that
    /// stays put does not open it again.
    public mutating func closed() {
        watchUntil = -.infinity
        clickUntil = -.infinity
        away = 0
    }
}

/// Which focused elements the keyboard types into.
public enum TextInput {
    /// - editable: the element's value can be set, so it is not read-only text.
    public static func accepts(role: String?, subrole: String?, editable: Bool) -> Bool {
        guard editable else { return false }
        if subrole == "AXSearchField" || subrole == "AXSecureTextField" { return true }
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role ?? "")
    }
}
