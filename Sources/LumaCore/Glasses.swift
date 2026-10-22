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
    var onEvent: ((GlassesEvent) -> Void)? { get set }
    func stop()
}
