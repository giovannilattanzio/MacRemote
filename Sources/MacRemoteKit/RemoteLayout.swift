import Foundation

/// Which buttons to draw on a Fire TV remote. Every remote has the D-pad,
/// Back/Home/Menu, and Rewind/Play/Fast Forward. Some add the Alexa button
/// (with its light bar), some add TV controls (power, volume, mute). The
/// product id says which when it is known, and a press of one proves it.
public struct RemoteLayout: Equatable, Sendable {
    public var hasVoice: Bool
    public var hasTVControls: Bool

    public init(hasVoice: Bool = false, hasTVControls: Bool = false) {
        self.hasVoice = hasVoice
        self.hasTVControls = hasTVControls
    }

    /// Product ids seen on real remotes.
    private static let known: [Int: RemoteLayout] = [
        0x0404: RemoteLayout(hasVoice: false, hasTVControls: false),
    ]

    static let voiceButtons: Set<RemoteButton> = [.voice]
    static let tvButtons: Set<RemoteButton> = [.power, .volumeUp, .volumeDown, .mute]
    static let coreButtons: Set<RemoteButton> = [.up, .down, .left, .right, .select, .back, .home, .menu,
                                                 .rewind, .playPause, .fastForward]

    /// Optional buttons are drawn only when known for the product or seen pressed.
    public static func forRemote(productID: Int, seen: Set<RemoteButton> = []) -> RemoteLayout {
        var layout = known[productID] ?? RemoteLayout()
        if !seen.isDisjoint(with: voiceButtons) { layout.hasVoice = true }
        if !seen.isDisjoint(with: tvButtons) { layout.hasTVControls = true }
        return layout
    }

    /// The buttons drawn, so the app can tell which presses light up the picture.
    public var buttons: Set<RemoteButton> {
        var all = Self.coreButtons
        if hasVoice { all.formUnion(Self.voiceButtons) }
        if hasTVControls { all.formUnion(Self.tvButtons) }
        return all
    }

    // MARK: Geometry, in widths of the remote (the drawing scales with its width)

    /// Center of the power button, when there is one.
    public var powerY: Double { 0.21 }
    /// Center of the Alexa button, when there is one; the light bar sits above it.
    public var voiceY: Double { 0.57 }
    /// Center of the D-pad. It moves up into the space a missing Alexa or power button leaves.
    public var padY: Double { hasVoice ? 1.45 : (hasTVControls ? 0.95 : 0.70) }
    /// Centers of the button rows below the D-pad, top to bottom.
    public var rowYs: [Double] {
        let back = padY + 0.92
        let media = back + 0.42
        return hasTVControls ? [back, media, media + 0.44] : [back, media]
    }
    /// Length over width. The real remotes leave a long, empty grip below the buttons.
    public var aspect: Double { (rowYs.last ?? padY) + 1.41 }
}
