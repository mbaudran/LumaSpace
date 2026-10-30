import Foundation

public enum LevelKind: Hashable, Sendable { case brightness, volume }

public enum GlassesStatus: Equatable, Sendable {
    case simulated(reason: String)
    case connected(name: String)
    case disconnected

    public var text: String {
        switch self {
        case .simulated(let reason): "Simulator — \(reason)"
        case .connected(let name): "Connected — \(name)"
        case .disconnected: "Disconnected"
        }
    }
}

public enum DisplayRate: Int, CaseIterable, Sendable { case hz60 = 60, hz90 = 90, hz120 = 120 }

/// VITURE 3D SBS display modes to try, best first: 3840×1200 @ 90 Hz (0x45), then @ 60 Hz (0x42).
public func stereoDisplayModes(for rate: DisplayRate) -> [Int32] {
    rate == .hz60 ? [0x42] : [0x45, 0x42]
}

public enum GlassesEvent: Sendable { case levelChanged(LevelKind, Int), disconnected }

/// Everything the app needs from a pair of glasses, real or simulated.
@MainActor
public protocol GlassesLink: AnyObject {
    var status: GlassesStatus { get }
    /// Latest orientation in the render frame. Safe to call from any thread.
    func rawOrientation() -> Quat
    func level(_ k: LevelKind) -> Int?
    func maxLevel(_ k: LevelKind) -> Int?
    func setLevel(_ k: LevelKind, _ v: Int)
    func setRate(_ r: DisplayRate)
    /// On: switch to a 3D side-by-side mode; returns whether the glasses accepted one.
    /// Off: back to 2D at `rate`.
    func setStereo(_ on: Bool, rate: DisplayRate) -> Bool
    /// Whether the electrochromic lenses are darkened; nil when the glasses can't tell.
    func lensTint() -> Bool?
    func setLensTint(_ on: Bool)
    var onEvent: ((GlassesEvent) -> Void)? { get set }
    func stop()
}
