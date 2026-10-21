import Foundation

/// Identity of a capture source; window titles change, ids don't.
public enum SourceKey: Hashable, Sendable { case display(UInt32), window(UInt32) }

public enum PanelSource: Codable, Hashable, Sendable {
    case display(id: UInt32, name: String)
    case window(id: UInt32, app: String, title: String)
    case placeholder(String)

    public var key: SourceKey? {
        switch self {
        case .display(let id, _): .display(id)
        case .window(let id, _, _): .window(id)
        case .placeholder: nil
        }
    }

    public var label: String {
        switch self {
        case .display(_, let name): name
        case .window(_, let app, let title): title.isEmpty ? app : "\(app) — \(title)"
        case .placeholder(let name): name
        }
    }
}

public enum SceneLimits {
    public static let pitch = -75.0...75.0
    public static let distance = 0.5...10.0
    public static let width = 0.2...12.0
    public static let aspect = 0.1...10.0
}

/// Wraps degrees into (−180, 180].
public func wrapYaw(_ d: Double) -> Double {
    var r = d.truncatingRemainder(dividingBy: 360)
    if r <= -180 { r += 360 }
    if r > 180 { r -= 360 }
    return r
}

func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }

/// A virtual screen. `yaw`/`pitch` are degrees of the panel centre as seen from the head
/// (yaw > 0 is left, pitch > 0 is up); `distance` and `width` are metres.
public struct Panel: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var source: PanelSource
    public var yaw: Double
    public var pitch: Double
    public var distance: Double
    public var width: Double
    public var aspect: Double
    public var groupID: UUID?
    public var available = true

    enum CodingKeys: String, CodingKey { case id, source, yaw, pitch, distance, width, aspect, groupID }

    public init(id: UUID = UUID(), source: PanelSource, yaw: Double, pitch: Double, distance: Double,
                width: Double, aspect: Double, groupID: UUID? = nil) {
        self.id = id; self.source = source; self.yaw = yaw; self.pitch = pitch
        self.distance = distance; self.width = width; self.aspect = aspect; self.groupID = groupID
    }

    public var height: Double { width / aspect }
    public var angularWidth: Double { 2 * atan(width / 2 / distance) * 180 / .pi }
    public var angularHeight: Double { 2 * atan(height / 2 / distance) * 180 / .pi }

    public func contains(yaw y: Double, pitch p: Double) -> Bool {
        abs(wrapYaw(y - yaw)) <= angularWidth / 2 && abs(p - pitch) <= angularHeight / 2
    }

    /// Panel centre in the render frame.
    public func worldCenter() -> Vec3 {
        Quat(yaw: yaw * .pi / 180, pitch: pitch * .pi / 180, roll: 0).rotate(Vec3(x: 0, y: 0, z: -1)) * distance
    }
}
