import Foundation
import LumaCore

func snappingChecks() {
    // 1 m wide at 2 m ≈ 28.07°; A's right edge (yaw > 0 is left) sits at −14.04°.
    let angW = 2 * atan(0.25) * 180 / .pi

    check("edges abut when within threshold") {
        let s = SpatialScene()
        _ = s.add(makePanel(yaw: 0))
        let b = s.add(makePanel(yaw: -60))
        s.move(b, toYaw: -29.0, pitch: 0)
        expectNear(s.panel(b)!.yaw, -angW, tol: 1e-6)
    }
    check("grid snap when no edge is near") {
        let s = SpatialScene()
        _ = s.add(makePanel(yaw: 0))
        let b = s.add(makePanel(yaw: -90))
        s.move(b, toYaw: -60.3, pitch: 0.4)
        expectNear(s.panel(b)!.yaw, -60)
        expectNear(s.panel(b)!.pitch, 0)
    }
    check("snapping disabled keeps the exact target") {
        let s = SpatialScene()
        s.snap.enabled = false
        _ = s.add(makePanel(yaw: 0))
        let b = s.add(makePanel(yaw: -90))
        s.move(b, toYaw: -29.0, pitch: 1.3)
        expectNear(s.panel(b)!.yaw, -29.0)
        expectNear(s.panel(b)!.pitch, 1.3)
    }
    check("group members move together") {
        let s = SpatialScene()
        let a = s.add(makePanel(yaw: 0))
        let b = s.add(makePanel(yaw: -40))
        s.group([a, b])
        s.move(a, toYaw: 10, pitch: 0)
        expectNear(s.panel(a)!.yaw, 10)
        expectNear(s.panel(b)!.yaw, -30)
    }
    check("ungrouped panel stays put") {
        let s = SpatialScene()
        let a = s.add(makePanel(yaw: 0))
        let b = s.add(makePanel(yaw: -40))
        s.group([a, b])
        s.ungroup(b)
        s.move(a, toYaw: 10, pitch: 0)
        expectNear(s.panel(b)!.yaw, -40)
    }
}
