import Foundation
import LumaCore

func grabChecks() {
    check("grab selects the panel under the gaze") {
        let s = SpatialScene()
        let id = s.add(makePanel(yaw: 0))
        let g = Grab()
        expectEqual(g.begin(scene: s, yaw: 2, pitch: 1), id)
        expectEqual(s.selectedID, id)
    }
    check("grab on empty space does nothing") {
        let s = SpatialScene()
        _ = s.add(makePanel(yaw: 0))
        let g = Grab()
        expectEqual(g.begin(scene: s, yaw: 120, pitch: 0), nil)
        g.drag(scene: s, dx: 100, dy: 0)
        expectNear(s.panels[0].yaw, 0)
    }
    check("mouse right moves the panel right, mouse up moves it up") {
        let s = SpatialScene()
        let id = s.add(makePanel(yaw: 0))
        let g = Grab()
        _ = g.begin(scene: s, yaw: 0, pitch: 0)
        g.drag(scene: s, dx: 100, dy: 50)
        expectNear(s.panel(id)!.yaw, -10)
        expectNear(s.panel(id)!.pitch, 5)
    }
    check("small drags accumulate past the snap grid") {
        let s = SpatialScene()
        let id = s.add(makePanel(yaw: 0))
        let g = Grab()
        _ = g.begin(scene: s, yaw: 0, pitch: 0)
        for _ in 0..<5 { g.drag(scene: s, dx: 10, dy: 0) }
        expectNear(s.panel(id)!.yaw, -5)
    }
    check("dragging past the pitch limit then back responds at once") {
        let s = SpatialScene()
        let id = s.add(makePanel(yaw: 0))
        let g = Grab()
        _ = g.begin(scene: s, yaw: 0, pitch: 0)
        g.drag(scene: s, dx: 0, dy: 2000)
        expectNear(s.panel(id)!.pitch, 75)
        g.drag(scene: s, dx: 0, dy: -100)
        expectNear(s.panel(id)!.pitch, 65)
    }
    check("after end, drags are ignored") {
        let s = SpatialScene()
        let id = s.add(makePanel(yaw: 0))
        let g = Grab()
        _ = g.begin(scene: s, yaw: 0, pitch: 0)
        g.end()
        g.drag(scene: s, dx: 100, dy: 0)
        expectNear(s.panel(id)!.yaw, 0)
    }
}
