import Foundation
import LumaCore

func stereoChecks() {
    check("eyes sit ipd apart on head-local x, symmetric") {
        let l = eyeOffset(.left, head: .identity, ipd: 0.063), r = eyeOffset(.right, head: .identity, ipd: 0.063)
        expectNear(l.x, -0.0315); expectNear(r.x, 0.0315); expectNear(l.y, 0); expectNear(r.z, 0)
    }
    check("eye offsets turn with the head") {
        let h = Quat(yaw: .pi / 2, pitch: 0, roll: 0)
        let r = eyeOffset(.right, head: h, ipd: 0.06)
        expectNear((r - eyeOffset(.left, head: h, ipd: 0.06)).length, 0.06)
        expectNear(abs(r.z), 0.03, tol: 1e-9); expectNear(r.x, 0, tol: 1e-9)
    }
    check("viewports split the drawable exactly, odd widths too") {
        for w in [3840, 1920, 1281] {
            let l = eyeViewport(.left, drawableWidth: w, drawableHeight: 1200)
            let r = eyeViewport(.right, drawableWidth: w, drawableHeight: 1200)
            expectEqual(l.x, 0); expectEqual(r.x, l.width); expectEqual(l.width + r.width, w); expectEqual(r.height, 1200)
        }
    }
    check("each eye's aspect uses half the width") {
        expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 1200), 1.6)
        expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 0), 1.6)
    }
}

@MainActor
func stereoModeChecks() {
    check("90 and 120 Hz ask for 3D at 90 Hz, then 60 Hz") {
        expectEqual(stereoDisplayModes(for: .hz90), [0x45, 0x42])
        expectEqual(stereoDisplayModes(for: .hz120), [0x45, 0x42])
        expectEqual(stereoDisplayModes(for: .hz60), [0x42])
    }
    check("simulated glasses accept stereo and drop it again") {
        let g = SimulatedGlasses(reason: "test")
        expect(g.setStereo(true, rate: .hz90)); expect(g.stereo)
        expect(g.setStereo(false, rate: .hz60)); expect(!g.stereo)
    }
}

func cinemaSceneChecks() {
    check("default row puts the screen 10 m straight ahead") {
        let l = cinemaLayout(CinemaSettings(), sourceAspect: 16.0 / 9)
        expectNear(l.viewer.z - l.screenCenter.z, 10); expectNear(l.screenCenter.x, 0); expectNear(l.screenWidth, 8)
    }
    check("closer rows are nearer the screen") {
        var s = CinemaSettings(); s.row = 0
        let front = cinemaLayout(s, sourceAspect: nil); s.row = 6
        expect(cinemaLayout(s, sourceAspect: nil).viewer.z - front.viewer.z > 5)
    }
    check("screen, viewer and every seat are inside the room; seats stay below the eyes") {
        let l = cinemaLayout(CinemaSettings(), sourceAspect: 2.39)
        func inside(_ p: Vec3) -> Bool {
            abs(p.x - l.room.center.x) <= l.room.size.x / 2 && abs(p.y - l.room.center.y) <= l.room.size.y / 2
                && abs(p.z - l.room.center.z) <= l.room.size.z / 2
        }
        expect(inside(l.screenCenter)); expect(inside(l.viewer)); expectEqual(l.seats.count, 84)
        // A seat's top stays below the eye height of someone sitting in that row.
        expect(l.seats.allSatisfy { inside($0.center) && $0.center.y + $0.size.y / 2 < 0.15 * ($0.center.z - 0.25) + 1.15 })
    }
    check("settings clamp and lights cycle") {
        let c = CinemaSettings(row: 12, screenScale: .nan, lights: .lit, ipd: 0.2).clamped
        expectEqual(c.row, 6); expectNear(c.screenScale, 1); expectNear(c.ipd, 0.075)
        expectEqual(RoomLights.lit.next, .dark); expectNear(RoomLights.dim.ambient, 0.08)
    }
    check("a missing or silly source aspect falls back to 16:9") {
        expectNear(cinemaLayout(CinemaSettings(), sourceAspect: nil).screenHeight, 4.5)
        expectNear(cinemaLayout(CinemaSettings(), sourceAspect: 0).screenHeight, 4.5)
    }
}
