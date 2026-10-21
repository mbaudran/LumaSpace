import Foundation

/// Stand-in glasses driven by mouse/keyboard input, used whenever real glasses aren't available.
public final class SimulatedGlasses: GlassesLink {
    public var yaw = 0.0, pitch = 0.0, roll = 0.0  // radians
    public let status: GlassesStatus
    public var onEvent: ((GlassesEvent) -> Void)?
    private var levels: [LevelKind: Int] = [.brightness: 4, .volume: 4]

    public init(reason: String) { status = .simulated(reason: reason) }

    public func rawOrientation() -> Quat { Quat(yaw: yaw, pitch: pitch, roll: roll) }
    public func level(_ k: LevelKind) -> Int? { levels[k] }
    public func maxLevel(_ k: LevelKind) -> Int? { 8 }

    public func setLevel(_ k: LevelKind, _ v: Int) {
        let v = min(max(v, 0), 8)
        levels[k] = v
        onEvent?(.levelChanged(k, v))
    }

    public func setRate(_ r: DisplayRate) {}
    public func stop() {}
}
