import AppKit
import LumaCore
import MetalKit

/// Direction (degrees, yaw > 0 left, pitch > 0 up) through a point of a view, given the head orientation.
func gazeDirection(at point: CGPoint, in size: CGSize, head: Quat) -> (yaw: Double, pitch: Double) {
    let aspect = size.height > 0 ? Double(size.width / size.height) : 16.0 / 9
    let t = tan(verticalFOV(aspect: aspect) / 2)
    let nx = 2 * Double(point.x / size.width) - 1, ny = 2 * Double(point.y / size.height) - 1
    let d = head.rotate(Vec3(x: nx * t * aspect, y: ny * t, z: -1)).normalized
    return (atan2(-d.x, -d.z) * 180 / .pi, asin(d.y) * 180 / .pi)
}

/// The preview's view: mouse and keyboard edit the layout and drive the simulated head.
@MainActor
final class LumaView: MTKView {
    var scene: SpatialScene!
    var head: () -> Quat = { .identity }
    var simulator: SimulatedGlasses?
    var onRecenter: () -> Void = {}
    var onEdit: () -> Void = {}
    var onKey: (NSEvent) -> Bool = { _ in false }

    private var dragOffset: (yaw: Double, pitch: Double)?
    private var lookDragging = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func gaze(_ e: NSEvent) -> (yaw: Double, pitch: Double) {
        gazeDirection(at: convert(e.locationInWindow, from: nil), in: bounds.size, head: head())
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        if e.modifierFlags.contains(.option) { lookDragging = true; return }
        let g = gaze(e)
        scene.selectedID = scene.hitTest(yaw: g.yaw, pitch: g.pitch)
        if let id = scene.selectedID, let p = scene.panel(id) {
            dragOffset = (wrapYaw(g.yaw - p.yaw), g.pitch - p.pitch)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        if lookDragging { look(e); return }
        guard let id = scene.selectedID, let off = dragOffset else { return }
        let g = gaze(e)
        scene.move(id, toYaw: g.yaw - off.yaw, pitch: g.pitch - off.pitch)
        onEdit()
    }

    override func mouseUp(with e: NSEvent) { dragOffset = nil; lookDragging = false }
    override func rightMouseDragged(with e: NSEvent) { look(e) }

    /// Dragging right looks right (yaw decreases); dragging up looks up.
    private func look(_ e: NSEvent) {
        guard let sim = simulator else { return }
        let k = 0.25 * Double.pi / 180
        sim.yaw -= Double(e.deltaX) * k
        sim.pitch = min(max(sim.pitch - Double(e.deltaY) * k, -1.3), 1.3)
    }

    override func scrollWheel(with e: NSEvent) {
        guard let id = scene.selectedID, let p = scene.panel(id), e.scrollingDeltaY != 0 else { return }
        scene.resize(id, width: p.width * (e.scrollingDeltaY > 0 ? 1.05 : 1 / 1.05))
        onEdit()
    }

    override func keyDown(with e: NSEvent) {
        if e.charactersIgnoringModifiers?.lowercased() == "r" { onRecenter(); return }
        if !onKey(e) { super.keyDown(with: e) }
    }
}
