import Foundation

/// Real glasses count as gone when their USB device is missing for two polls, or — after a short
/// start-up grace period — when the pose stream goes silent (a fast replug leaves a dead session).
/// Never while they switch display modes, which can pause both.
public func glassesLost(missedPolls: Int, sampleAge: Double?, connectedFor: Double,
                        startupGrace: Double = 3, silence: Double = 1.5, switchingModes: Bool = false) -> Bool {
    if switchingModes { return false }
    if missedPolls >= 2 { return true }
    guard connectedFor > startupGrace else { return false }
    guard let age = sampleAge else { return true }
    return age > silence
}

/// Remembers failures per key and refuses retries until `delay` seconds have passed.
public final class RetryGate<Key: Hashable> {
    public let delay: Double
    private var failedAt: [Key: Double] = [:]

    public init(delay: Double) { self.delay = delay }

    public func allowed(_ k: Key, now: Double) -> Bool {
        guard let t = failedAt[k] else { return true }
        return now - t >= delay
    }

    public func failed(_ k: Key, now: Double) { failedAt[k] = now }
    public func succeeded(_ k: Key) { failedAt[k] = nil }
}

/// ⌃⌥ is shared with the global shortcuts: only treat it as a grab once it has been held alone
/// for `holdDelay` seconds, and never after a shortcut fired during the same hold.
public struct GrabArming {
    public var holdDelay = 0.3
    private var heldSince: Double?
    private var cancelled = false

    public init() {}

    public mutating func update(held: Bool, now: Double) -> Bool {
        guard held else { heldSince = nil; cancelled = false; return false }
        if heldSince == nil { heldSince = now }
        return !cancelled && now - heldSince! >= holdDelay
    }

    public mutating func cancelUntilRelease() { cancelled = true }
}
