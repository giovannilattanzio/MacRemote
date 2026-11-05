import Foundation
import Testing
@testable import MacRemoteKit

private let down: UInt16 = 125

@Test func remoteArrowKeysAreRecognizedWhileHeld() {
    var keys = KeyGuard()
    keys.remote(.key(0x51), pressed: true, at: 10)
    #expect(keys.cameFromRemote(down, at: 10.01))
    // macOS's key repeat, long after the press, while the button is still down.
    #expect(keys.cameFromRemote(down, at: 12))
    keys.remote(.key(0x51), pressed: false, at: 12.5)
    // The key-up macOS makes right after the release.
    #expect(keys.cameFromRemote(down, at: 12.55))
}

@Test func keyboardKeysGetThrough() {
    var keys = KeyGuard()
    keys.remote(.key(0x51), pressed: true, at: 10)
    keys.remote(.key(0x51), pressed: false, at: 10.1)
    #expect(!keys.cameFromRemote(down, at: 20))
    // Another key at the same moment is the keyboard's.
    #expect(!keys.cameFromRemote(126, at: 10.05))
}

@Test func consumerUsagesAreNotKeys() {
    #expect(KeyGuard.keyCode(for: .consumer(0x42)) == nil)
    #expect(KeyGuard.keyCode(for: .key(0x28)) == 36)
}
