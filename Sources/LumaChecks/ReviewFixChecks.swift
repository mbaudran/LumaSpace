import Foundation
import LumaCore

func reviewFixChecks() {
    check("group keeps its shape at the pitch limit") {
        let s = SpatialScene()
        let ps = Preset.stacked.panels(sources: [], distance: 2)
        s.replaceAll(ps)
        s.snap.enabled = false
        let top = s.panels[0], bottom = s.panels[1]
        let gap = top.pitch - bottom.pitch
        // Dragging the top panel down: the bottom row reaches −75° first.
        s.move(top.id, toYaw: top.yaw, pitch: -120)
        expectNear(s.panel(top.id)!.pitch - s.panel(bottom.id)!.pitch, gap, tol: 1e-9)
        expectNear(s.panel(bottom.id)!.pitch, -75)
    }
    check("bad aspect from disk is clamped") {
        let s = SpatialScene()
        let id = s.add(makePanel(aspect: 0))
        expect(s.panel(id)!.aspect >= SceneLimits.aspect.lowerBound)
        expect(s.panel(id)!.height.isFinite)
    }
    check("layout distance from disk is clamped") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("luma-\(UUID().uuidString)")
        let store = LayoutStore(url: dir.appendingPathComponent("layout.json"))
        var f = LayoutFile.default
        f.distance = 0
        try store.save(f)
        expectNear(store.load().distance, SceneLimits.distance.lowerBound)
    }
    check("glasses lost: missing for two polls") {
        expect(glassesLost(missedPolls: 2, sampleAge: 0.01, connectedFor: 10))
        expect(!glassesLost(missedPolls: 1, sampleAge: 0.01, connectedFor: 10))
    }
    check("glasses lost: pose stream went silent (fast replug)") {
        expect(glassesLost(missedPolls: 0, sampleAge: 2.0, connectedFor: 10))
        expect(glassesLost(missedPolls: 0, sampleAge: nil, connectedFor: 10))
    }
    check("glasses not lost while still starting up") {
        expect(!glassesLost(missedPolls: 0, sampleAge: nil, connectedFor: 1))
    }
    check("retry gate backs off after a failure") {
        let g = RetryGate<Int>(delay: 10)
        expect(g.allowed(1, now: 0))
        g.failed(1, now: 0)
        expect(!g.allowed(1, now: 5))
        expect(g.allowed(2, now: 5))
        expect(g.allowed(1, now: 10.5))
        g.failed(1, now: 11); g.succeeded(1)
        expect(g.allowed(1, now: 11))
    }
    check("grab arms only after ⌃⌥ is held a moment") {
        var a = GrabArming()
        expect(!a.update(held: true, now: 0))
        expect(!a.update(held: true, now: 0.1))
        expect(a.update(held: true, now: 0.35))
        expect(!a.update(held: false, now: 0.4))
    }
    check("a shortcut press cancels the grab until release") {
        var a = GrabArming()
        _ = a.update(held: true, now: 0)
        a.cancelUntilRelease()
        expect(!a.update(held: true, now: 1.0))
        _ = a.update(held: false, now: 1.1)
        _ = a.update(held: true, now: 2.0)
        expect(a.update(held: true, now: 2.4))
    }
}
