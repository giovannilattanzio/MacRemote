import Foundation
import Testing
@testable import MacRemoteKit

@Test("Fire TV usages resolve to buttons", arguments: [
    (HIDUsage.key(0x52), RemoteButton.up),
    (HIDUsage.consumer(0x42), RemoteButton.up),
    (HIDUsage.key(0x28), RemoteButton.select),
    (HIDUsage.consumer(0x41), RemoteButton.select),
    (HIDUsage.consumer(0x224), RemoteButton.back),
    (HIDUsage.key(0xF1), RemoteButton.back),
    (HIDUsage.key(0x58), RemoteButton.select),
    (HIDUsage.consumer(0x223), RemoteButton.home),
    (HIDUsage.consumer(0x40), RemoteButton.menu),
    (HIDUsage.consumer(0xCD), RemoteButton.playPause),
    (HIDUsage.consumer(0xB4), RemoteButton.rewind),
    (HIDUsage.consumer(0xB3), RemoteButton.fastForward),
    (HIDUsage.consumer(0xE9), RemoteButton.volumeUp),
])
func resolves(_ usage: HIDUsage, button: RemoteButton) {
    #expect(RemoteButton(usage: usage) == button)
    #expect(RemoteKey(usage: usage) == RemoteKey(button))
}

@Test func unknownUsagesBecomeLearnedKeys() {
    let key = RemoteKey(usage: .consumer(0x1A0))
    #expect(key.button == nil)
    #expect(key.raw == "usage:0C:01A0")
    #expect(key.title == "Button 0C:01A0")
}

@Test func placeholderUsagesAreNotButtons() {
    #expect(!HIDUsage.key(0x01).isButton)
    #expect(!HIDUsage(page: 0x07, usage: 0xFFFF_FFFF).isButton)
    #expect(!HIDUsage.consumer(0x01).isButton)
    #expect(HIDUsage.key(0x52).isButton)
    #expect(HIDUsage.consumer(0x224).isButton)
    #expect(HIDUsage.key(0xF1).isButton)
}

@Test func recognizesFireTVRemotes() {
    #expect(FireTVRemote.isFireTVRemote(vendorID: 0x1949, product: "Remote"))
    #expect(FireTVRemote.isFireTVRemote(vendorID: 0, product: "Amazon Fire TV Remote"))
    #expect(!FireTVRemote.isFireTVRemote(vendorID: 0x05AC, product: "Magic Keyboard"))
}

@Test func standardProfileCoversTheDPadInBothModes() {
    let profile = Profile.standard
    #expect(profile.action(for: RemoteKey(.up), in: .navigation) == .arrowUp)
    #expect(profile.action(for: RemoteKey(.up), in: .pointer) == .pointerUp)
    #expect(profile.action(for: RemoteKey(.select), in: .pointer) == .leftClick)
    for mode in RemoteMode.allCases {
        #expect(profile.action(for: RemoteKey(.menu), in: mode) == .toggleMode)
    }
}

@Test func profileRoundTripsThroughJSON() throws {
    var profile = Profile.standard
    profile.set(.fullScreen, for: RemoteKey(.guide), in: .navigation)
    profile.learn(RemoteKey(usage: .consumer(0x1A0)))
    let data = try JSONEncoder().encode(profile)
    let back = try JSONDecoder().decode(Profile.self, from: data)
    #expect(back == profile)
    #expect(back.keys.last == RemoteKey(usage: .consumer(0x1A0)))
}

@Test func learningKeepsExistingBindings() {
    var profile = Profile.standard
    profile.learn(RemoteKey(.up))
    #expect(profile.action(for: RemoteKey(.up), in: .navigation) == .arrowUp)
}

@Test func holdBehavior() {
    #expect(RemoteAction.pointerUp.hold == .continuous)
    #expect(RemoteAction.scrollDown.hold == .continuous)
    #expect(RemoteAction.arrowLeft.hold == .repeats)
    #expect(RemoteAction.volumeUp.hold == .repeats)
    #expect(RemoteAction.leftClick.hold == .once)
    #expect(RemoteAction.switchApp.hold == .once)
}

@Test func nativeActionsMatchKeyboardBehavior() {
    #expect(RemoteAction.native(for: .key(0x52)) == .arrowUp)
    #expect(RemoteAction.native(for: .key(0x58)) == .returnKey)
    #expect(RemoteAction.native(for: .consumer(0xCD)) == nil)
    #expect(RemoteAction.native(for: .consumer(0x224)) == nil)
}

@Test func pointerAcceleratesAndCaps() {
    let motion = PointerMotion(baseSpeed: 100, maxSpeed: 1000, rampTime: 1)
    #expect(motion.speed(heldFor: 0) == 100)
    #expect(motion.speed(heldFor: 0.5) == 325)
    #expect(motion.speed(heldFor: 5) == 1000)
    #expect(PointerMotion(sliderValue: 1).maxSpeed > PointerMotion(sliderValue: 0).maxSpeed)
}

@Test func keyRepeatTiming() {
    let rep = KeyRepeat(delay: 0.4, interval: 0.1)
    #expect(rep.presses(heldFor: 0.1) == 1)
    #expect(rep.presses(heldFor: 0.4) == 2)
    #expect(rep.presses(heldFor: 0.65) == 4)
}

@Test func doubleClicks() {
    var counter = ClickCounter(window: 0.4)
    #expect(counter.click(at: 10) == 1)
    #expect(counter.click(at: 10.2) == 2)
    #expect(counter.click(at: 11) == 1)
}

@Test func keyBlockCoversTheRemoteAndClears() throws {
    #expect(KeyBlock.code(.key(0x51)) == 0x7_0000_0051)
    #expect(KeyBlock.code(.consumer(0xCD)) == 0xC_0000_00CD)
    let usages = Set(KeyBlock.blockedUsages)
    for button in RemoteButton.allCases {
        for usage in button.usages { #expect(usages.contains(usage)) }
    }
    let set = KeyBlock.setting(blocked: true)
    let json = try JSONSerialization.jsonObject(with: Data(set.utf8)) as? [String: [[String: UInt64]]]
    #expect(json?["UserKeyMapping"]?.count == usages.count)
    #expect(json?["UserKeyMapping"]?.allSatisfy { $0["HIDKeyboardModifierMappingDst"] == 0x7_0000_0000 } == true)
    #expect(KeyBlock.setting(blocked: false) == #"{"UserKeyMapping":[]}"#)
    #expect(KeyBlock.matching(vendorID: 6473, productID: 1028) == #"{"VendorID":6473,"ProductID":1028}"#)
}

@Test func layoutFollowsProductAndPresses() {
    let plain = RemoteLayout.forRemote(productID: 0x0404)
    #expect(!plain.hasVoice && !plain.hasTVControls)
    #expect(RemoteLayout.forRemote(productID: 0x0404, seen: [.select, .home]) == plain)
    #expect(RemoteLayout.forRemote(productID: 0x0404, seen: [.voice]).hasVoice)
    #expect(RemoteLayout.forRemote(productID: 0x0404, seen: [.volumeUp]).hasTVControls)
    #expect(!RemoteLayout.forRemote(productID: 0x9999).hasVoice)
    #expect(!plain.buttons.contains(.voice) && !plain.buttons.contains(.mute))
    #expect(RemoteLayout(hasVoice: true, hasTVControls: true).buttons.isSuperset(of: [.voice, .power]))
}

@Test func layoutMakesRoomForOptionalButtons() {
    let plain = RemoteLayout()
    let voice = RemoteLayout(hasVoice: true)
    let full = RemoteLayout(hasVoice: true, hasTVControls: true)
    #expect(plain.padY < voice.padY)
    #expect(plain.aspect < voice.aspect)
    #expect(voice.aspect < full.aspect)
    #expect(full.rowYs.count == 3 && plain.rowYs.count == 2)
    // The old drawing: Alexa remote, 4.2 widths long.
    #expect(abs(voice.aspect - 4.2) < 0.01)
}

@Test func batteryReadsRegistryValues() {
    #expect(Battery(registryValue: NSNumber(value: 72))?.percent == 72)
    #expect(Battery(registryValue: 72)?.percent == 72)
    #expect(Battery(registryValue: "72") == nil)
    #expect(Battery(registryValue: nil) == nil)
    #expect(Battery(percent: 101) == nil)
    #expect(Battery(percent: -1) == nil)
}

@Test("Battery symbols and low warning", arguments: [
    (100, "battery.100", false), (75, "battery.75", false), (50, "battery.50", false),
    (21, "battery.25", false), (20, "battery.25", true), (5, "battery.0", true),
])
func batterySymbols(_ percent: Int, symbol: String, low: Bool) {
    let battery = Battery(percent: percent)!
    #expect(battery.symbol == symbol)
    #expect(battery.isLow == low)
    #expect(battery.title == "\(percent)%")
}
