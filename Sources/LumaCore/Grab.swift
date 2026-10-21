import Foundation

/// Hands-free editing in the glasses: grab the panel you're looking at, then move it with mouse deltas.
public final class Grab {
    public private(set) var panelID: UUID?
    public var degreesPerPoint = 0.1
    private var target: (yaw: Double, pitch: Double) = (0, 0)

    public init() {}

    /// Selects the panel under the gaze direction (degrees) and starts a grab.
    public func begin(scene: SpatialScene, yaw: Double, pitch: Double) -> UUID? {
        panelID = scene.hitTest(yaw: yaw, pitch: pitch)
        if let id = panelID, let p = scene.panel(id) {
            scene.selectedID = id
            target = (p.yaw, p.pitch)
        }
        return panelID
    }

    /// `dx` > 0 is mouse right (panel moves right, yaw decreases); `dy` > 0 is mouse up.
    /// The unsnapped target accumulates so small moves can cross snap points.
    public func drag(scene: SpatialScene, dx: Double, dy: Double) {
        guard let id = panelID else { return }
        target.yaw -= dx * degreesPerPoint
        target.pitch = clamp(target.pitch + dy * degreesPerPoint, SceneLimits.pitch)
        scene.move(id, toYaw: target.yaw, pitch: target.pitch)
    }

    public func end() { panelID = nil }
}
