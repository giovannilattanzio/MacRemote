import Foundation
import Testing
@testable import MacRemoteKit

@Test func everyRowIsTheSameWidth() {
    for rows in [OnScreenKeyboard.letters, OnScreenKeyboard.symbols] {
        for row in rows { #expect(row.reduce(0) { $0 + $1.width } == OnScreenKeyboard.rowUnits) }
    }
}

@Test func movingWrapsAroundTheEdges() {
    var keyboard = OnScreenKeyboard()
    keyboard.move(.left)
    #expect(keyboard.focused.kind == .delete)
    keyboard.move(.right)
    #expect(keyboard.focused.kind == .character("q"))
    keyboard.move(.up)
    #expect(keyboard.focused.kind == .layer)
}

@Test func movingOverSpaceComesBackToTheSameColumn() {
    var keyboard = OnScreenKeyboard()
    for _ in 0..<5 { keyboard.move(.right) } // y
    keyboard.move(.down); keyboard.move(.down); keyboard.move(.down)
    #expect(keyboard.focused.kind == .space)
    keyboard.move(.down)
    #expect(keyboard.focused.kind == .character("y"))
}

@Test func shiftLastsOneLetterOrLocksWhenPressedTwice() {
    var keyboard = OnScreenKeyboard()
    keyboard.move(.down); keyboard.move(.down) // z row starts with Shift
    keyboard.move(.left); keyboard.move(.right)
    #expect(keyboard.focused.kind == .shift)
    #expect(keyboard.press() == nil)
    keyboard.move(.right)
    #expect(keyboard.press() == .text("Z"))
    #expect(keyboard.press() == .text("z"))
    keyboard.move(.left)
    _ = keyboard.press(); _ = keyboard.press()
    #expect(keyboard.shift == .locked)
    keyboard.move(.right)
    #expect(keyboard.press() == .text("Z"))
    #expect(keyboard.press() == .text("Z"))
}

@Test func theLayerKeySwitchesToNumbers() {
    var keyboard = OnScreenKeyboard()
    keyboard.move(.up)
    #expect(keyboard.press() == nil)
    #expect(keyboard.label(for: keyboard.focused) == "ABC")
    keyboard.move(.down)
    #expect(keyboard.press() == .text("1"))
}

@Test func onlyEditableTextTakesTheKeyboard() {
    #expect(TextInput.accepts(role: "AXTextField", subrole: nil, editable: true))
    #expect(TextInput.accepts(role: "AXTextField", subrole: "AXSecureTextField", editable: true))
    #expect(TextInput.accepts(role: "AXTextArea", subrole: nil, editable: true))
    #expect(!TextInput.accepts(role: "AXTextArea", subrole: nil, editable: false))
    #expect(!TextInput.accepts(role: "AXButton", subrole: nil, editable: true))
}

@Test func theTriggerOpensOnlyForFocusTheRemoteMoved() {
    var trigger = KeyboardTrigger<Int>()
    #expect(trigger.observe(focus: 2, isText: true, showing: false, at: 0) == .none)
    trigger.remotePressed(click: false, at: 10) { 1 }
    #expect(trigger.observe(focus: 2, isText: true, showing: false, at: 10.2) == .show)
    trigger.closed()
    trigger.remotePressed(click: false, at: 20) { 2 }
    #expect(trigger.observe(focus: 2, isText: true, showing: false, at: 20.2) == .none)
    trigger.remotePressed(click: false, at: 30) { 2 }
    #expect(trigger.observe(focus: 3, isText: true, showing: false, at: 30 + KeyboardTrigger<Int>.watchTime + 1) == .none)
}
