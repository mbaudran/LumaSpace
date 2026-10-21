import Foundation
import LumaCore

func makePanel(_ source: PanelSource = .placeholder("P"), yaw: Double = 0, pitch: Double = 0,
               distance: Double = 2, width: Double = 1, aspect: Double = 16.0 / 9) -> Panel {
    Panel(source: source, yaw: yaw, pitch: pitch, distance: distance, width: width, aspect: aspect)
}

func sceneChecks() {
    check("angular width of 1 m at 1 m") {
        expectNear(makePanel(distance: 1, width: 1).angularWidth, 53.130102, tol: 1e-5)
    }
    check("contains wraps across ±180") {
        let p = makePanel(yaw: 170, distance: 1, width: 0.6)  // ≈ 33.4° wide; −175 is 15° away
        expect(p.contains(yaw: -175, pitch: 0))
        expect(!p.contains(yaw: 150, pitch: 0))
    }
    check("move/resize/distance clamp and wrap") {
        let s = SpatialScene()
        let id = s.add(makePanel())
        s.move(id, toYaw: 190, pitch: 120)
        expectNear(s.panels[0].yaw, -170)
        expectNear(s.panels[0].pitch, 75)
        s.resize(id, width: 0)
        expectNear(s.panels[0].width, 0.2)
        s.setDistance(0)
        expectNear(s.panels[0].distance, 0.5)
    }
    check("hitTest picks the nearest panel, nil when empty") {
        let s = SpatialScene()
        _ = s.add(makePanel(distance: 2))
        let near = s.add(makePanel(distance: 1))
        expectEqual(s.hitTest(yaw: 0, pitch: 0), near)
        expectEqual(s.hitTest(yaw: 120, pitch: 0), nil)
    }
    check("availability follows source keys, never removes panels") {
        let s = SpatialScene()
        _ = s.add(makePanel(.window(id: 9, app: "TextEdit", title: "Old")))
        _ = s.add(makePanel(.placeholder("Screen 2")))
        s.updateAvailability(available: [])
        expectEqual(s.panels.count, 2)
        expectEqual(s.panels[0].available, false)
        expectEqual(s.panels[1].available, true)
        s.updateAvailability(available: [.window(9)])
        expectEqual(s.panels[0].available, true)
    }
    check("codable round-trip drops availability") {
        var p = makePanel(.display(id: 1, name: "Built-in"), yaw: 12, pitch: -3)
        p.available = false
        let back = try JSONDecoder().decode(Panel.self, from: JSONEncoder().encode(p))
        expectEqual(back.id, p.id); expectEqual(back.source, p.source)
        expectNear(back.yaw, 12); expectNear(back.pitch, -3)
        expectEqual(back.available, true)
    }
}
