import Foundation

/// Pointer speed while a direction is held: slow at first for precision,
/// then faster to cross the screen.
public struct PointerMotion: Equatable, Sendable {
    /// Points per second at the start of a press.
    public var baseSpeed: Double
    /// Points per second after `rampTime`.
    public var maxSpeed: Double
    /// Seconds to reach full speed.
    public var rampTime: Double

    public init(baseSpeed: Double = 180, maxSpeed: Double = 1400, rampTime: Double = 1.2) {
        self.baseSpeed = baseSpeed
        self.maxSpeed = maxSpeed
        self.rampTime = rampTime
    }

    /// Builds the motion from the Settings slider, 0 (slow) to 1 (fast).
    public init(sliderValue: Double) {
        let s = min(max(sliderValue, 0), 1)
        self.init(baseSpeed: 80 + 200 * s, maxSpeed: 600 + 1800 * s, rampTime: 1.4 - 0.6 * s)
    }

    /// Speed after holding for `held` seconds. Eases in, so the first
    /// fraction of a second stays precise.
    public func speed(heldFor held: Double) -> Double {
        guard held > 0, rampTime > 0 else { return baseSpeed }
        let t = min(held / rampTime, 1)
        return baseSpeed + (maxSpeed - baseSpeed) * t * t
    }
}

/// Key repeat for held buttons, like a keyboard: one press, a pause, then a steady stream.
public struct KeyRepeat: Equatable, Sendable {
    public var delay: Double
    public var interval: Double

    public init(delay: Double = 0.4, interval: Double = 0.07) {
        self.delay = delay
        self.interval = interval
    }

    /// How many presses should have fired after holding for `held` seconds,
    /// counting the first one at press time.
    public func presses(heldFor held: Double) -> Int {
        guard held >= delay else { return 1 }
        return 2 + Int(((held - delay) / interval).rounded(.down))
    }
}

/// A click soon after the last one at the same spot counts as a double click.
public struct ClickCounter: Sendable {
    public var window: Double
    private var lastTime: Double = -.infinity
    private var count = 0

    public init(window: Double = 0.4) { self.window = window }

    public mutating func click(at time: Double) -> Int {
        count = time - lastTime <= window ? min(count + 1, 3) : 1
        lastTime = time
        return count
    }
}
