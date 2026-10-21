import Foundation

public enum Axis: String, Codable, CaseIterable, Sendable { case yaw, pitch, roll }

/// Turns raw glasses orientation into the head orientation used for rendering:
/// relative to a recentered reference, with optional axis locks and smooth follow.
public final class HeadTracker {
    public var smoothFollow = false {
        didSet { if smoothFollow != oldValue { anchor = .identity } }
    }
    public var followRate = 2.0
    public var lockedAxes: Set<Axis> = []

    private var reference: Quat?
    private var anchor = Quat.identity

    public init() {}

    /// Uses only the yaw of `raw` so the world stays level after recentering.
    public func recenter(to raw: Quat) {
        reference = Quat(yaw: raw.yawPitchRoll.yaw, pitch: 0, roll: 0)
        anchor = .identity
    }

    public func update(raw: Quat, dt: Double) -> Quat {
        if reference == nil { recenter(to: raw) }
        var relative = (reference!.conjugate * raw).normalized

        if !lockedAxes.isEmpty {
            let e = relative.yawPitchRoll
            relative = Quat(yaw: lockedAxes.contains(.yaw) ? 0 : e.yaw,
                            pitch: lockedAxes.contains(.pitch) ? 0 : e.pitch,
                            roll: lockedAxes.contains(.roll) ? 0 : e.roll)
        }

        guard smoothFollow else { return relative }
        anchor = Quat.slerp(anchor, relative, 1 - exp(-followRate * dt))
        return (anchor.conjugate * relative).normalized
    }
}
