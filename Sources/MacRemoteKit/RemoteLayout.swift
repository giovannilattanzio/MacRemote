import Foundation

/// Which Fire TV remote to draw. The classic Alexa Voice Remote has no TV
/// controls; newer ones add power, volume, and mute. The product id picks
/// the layout when it is known, and a press of a TV control proves it.
public enum RemoteLayout: String, Sendable, CaseIterable {
    /// Microphone, D-pad, Back/Home/Menu, Rewind/Play/Fast Forward.
    case classic
    /// The classic buttons plus power, volume up/down, and mute.
    case tvControls

    /// Product ids seen on real remotes, by layout.
    private static let known: [Int: RemoteLayout] = [
        0x0404: .classic,
    ]

    public static func forRemote(productID: Int, seen: Set<RemoteButton> = []) -> RemoteLayout {
        if !seen.isDisjoint(with: tvButtons) { return .tvControls }
        return known[productID] ?? .classic
    }

    static let tvButtons: Set<RemoteButton> = [.power, .volumeUp, .volumeDown, .mute]

    /// The buttons drawn, so the app can tell which presses light up the picture.
    public var buttons: Set<RemoteButton> {
        let classic: Set<RemoteButton> = [.voice, .up, .down, .left, .right, .select, .back, .home, .menu,
                                          .rewind, .playPause, .fastForward]
        return self == .classic ? classic : classic.union(Self.tvButtons)
    }
}
