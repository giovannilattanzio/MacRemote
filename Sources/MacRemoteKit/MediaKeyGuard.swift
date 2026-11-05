import Foundation

/// Decides which media-key events to drop, so a remote's transport button
/// does only what MacRemote says. macOS 12 also turns a shared remote's
/// Play/Pause into the Play media key, which opens Music when no app is
/// playing; the key block in Devices does not stop it there.
///
/// The app tells the guard when the remote pressed or released a transport
/// button, and asks it about every media-key event that MacRemote did not post.
public struct MediaKeyGuard: Sendable {
    /// How far apart the remote's press and macOS's media key can be.
    public static let window: TimeInterval = 0.3
    /// How long a media key waits for the remote's press that may follow it.
    public static let holdDelay: TimeInterval = 0.1

    public enum Decision: Equatable, Sendable {
        /// Not from the remote: let it through.
        case pass
        /// Made from the remote's press: drop it.
        case drop
        /// Could be either: drop it now, ask `cameFromRemote` after `holdDelay`, and post it again if not.
        case hold
    }

    private var lastPress: [Int32: TimeInterval] = [:]

    public init() {}

    /// The remote's button went down or up.
    public mutating func remote(_ usage: HIDUsage, at time: TimeInterval) {
        guard let key = MediaKey(remoteUsage: usage) else { return }
        lastPress[key.rawValue] = time
    }

    public func cameFromRemote(_ key: Int32, at time: TimeInterval) -> Bool {
        guard let pressed = lastPress[key] else { return false }
        return abs(time - pressed) <= Self.window
    }

    /// - remoteShared: a remote in use is not seized, so macOS also reads it.
    public func decide(_ key: Int32, at time: TimeInterval, remoteShared: Bool) -> Decision {
        guard remoteShared, MediaKey(rawValue: key).map(Self.guarded.contains) == true else { return .pass }
        return cameFromRemote(key, at: time) ? .drop : .hold
    }

    /// The keys a remote's transport buttons make. Volume and brightness are left alone.
    static let guarded: Set<MediaKey> = [.play, .next, .previous, .fast, .rewind]
}
