import Foundation
import Testing
@testable import MacRemoteKit

private let player = "com.example.player"
private let playPause = RemoteKey(.playPause)

@Test func addingAnAppMakesPlayPauseSendSpace() {
    var overrides = AppOverrides()
    overrides.add(bundleID: player, name: "Player")
    #expect(overrides.action(for: playPause, app: player) == .space)
    // Adding twice keeps one entry.
    overrides.add(bundleID: player, name: "Player")
    #expect(overrides.apps.count == 1)
}

@Test func otherAppsAndButtonsFallBackToTheProfile() {
    var overrides = AppOverrides()
    overrides.add(bundleID: player, name: "Player")
    #expect(overrides.action(for: playPause, app: "com.apple.Music") == nil)
    #expect(overrides.action(for: playPause, app: nil) == nil)
    #expect(overrides.action(for: RemoteKey(.select), app: player) == nil)
}

@Test func buttonsCanBeChangedAndRemoved() {
    var overrides = AppOverrides()
    overrides.add(bundleID: player, name: "Player")
    overrides.set(.arrowLeft, for: RemoteKey(.rewind), app: player)
    #expect(overrides.action(for: RemoteKey(.rewind), app: player) == .arrowLeft)
    #expect(overrides.apps[0].keys == [playPause, RemoteKey(.rewind)])
    overrides.remove(playPause, app: player)
    #expect(overrides.action(for: playPause, app: player) == nil)
    overrides.remove(app: player)
    #expect(overrides.apps.isEmpty)
}

@Test func overridesSurviveSaving() throws {
    var overrides = AppOverrides()
    overrides.add(bundleID: player, name: "Player")
    overrides.set(.fullScreen, for: RemoteKey(.home), app: player)
    let data = try JSONEncoder().encode(overrides)
    #expect(try JSONDecoder().decode(AppOverrides.self, from: data) == overrides)
}
