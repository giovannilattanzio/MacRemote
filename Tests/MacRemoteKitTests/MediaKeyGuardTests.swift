import Foundation
import Testing
@testable import MacRemoteKit

private let play = MediaKey.play.rawValue

@Test func theRemotesPlayPauseMapsToThePlayKey() {
    #expect(MediaKey(remoteUsage: .consumer(0xCD)) == .play)
    #expect(MediaKey(remoteUsage: .consumer(0xB4)) == .rewind)
    #expect(MediaKey(remoteUsage: .key(0x28)) == nil)
}

@Test func macOSPlayKeyFromTheRemoteIsDropped() {
    var guardian = MediaKeyGuard()
    guardian.remote(.consumer(0xCD), at: 10)
    #expect(guardian.decide(play, at: 10.05, remoteShared: true) == .drop)
}

@Test func playKeyBeforeTheRemotePressIsHeldThenRecognized() {
    var guardian = MediaKeyGuard()
    #expect(guardian.decide(play, at: 10, remoteShared: true) == .hold)
    guardian.remote(.consumer(0xCD), at: 10.02)
    #expect(guardian.cameFromRemote(play, at: 10))
}

@Test func keyboardPlayKeyGetsThrough() {
    var guardian = MediaKeyGuard()
    guardian.remote(.consumer(0xCD), at: 10)
    // Long after the remote's press: held, then not from the remote, so posted again.
    #expect(guardian.decide(play, at: 20, remoteShared: true) == .hold)
    #expect(!guardian.cameFromRemote(play, at: 20))
    // No shared remote: nothing to guard.
    #expect(guardian.decide(play, at: 10, remoteShared: false) == .pass)
    // Volume is never touched.
    #expect(guardian.decide(MediaKey.soundUp.rawValue, at: 10, remoteShared: true) == .pass)
}
