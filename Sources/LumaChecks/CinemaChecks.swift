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

func cinemaCommandChecks() {
    check("cinema mode is in the palette as 'cinema', 'movie' and 'vr'") {
        expectEqual(paletteMatches("cinema", in: Command.all).first, .toggleCinemaMode)
        expect(paletteMatches("movie", in: Command.all).contains(.toggleCinemaMode))
        expect(paletteMatches("vr", in: Command.all).contains(.toggleCinemaMode))
    }
    check("closer/farther pick rows, bigger/smaller scale the screen") {
        let s = CinemaSettings()
        expectEqual(cinemaAdjusted(s, by: .nudgeDistance(-0.25))?.row, 2)
        expectEqual(cinemaAdjusted(s, by: .nudgeDistance(0.25))?.row, 4)
        expectNear(cinemaAdjusted(s, by: .resizeSelected(1.1))!.screenScale, 1.1)
        expectNear(cinemaAdjusted(s, by: .nudgeIPD(0.001))!.ipd, 0.064)
        expectEqual(cinemaAdjusted(s, by: .cycleRoomLights)?.lights, .lit)
        expectEqual(cinemaAdjusted(s, by: .recenter), nil)
    }
    check("cinema and game mode exclude each other; toggling again returns to panels") {
        expectEqual(outputMode(after: .panels, toggling: .cinema), .cinema)
        expectEqual(outputMode(after: .cinema, toggling: .cinema), .panels)
        expectEqual(outputMode(after: .game, toggling: .cinema), .cinema)
        expectEqual(outputMode(after: .cinema, toggling: .game), .game)
    }
    check("a layout file without cinema settings still loads") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("luma-cinema-\(UUID()).json")
        try #"{"version":1,"panels":[],"distance":2,"smoothFollow":false,"lockedAxes":[]}"#.write(to: url, atomically: true, encoding: .utf8)
        let f = LayoutStore(url: url).load()
        expectEqual(f.cinema, nil); expectNear(f.distance, 2)
        expect(!FileManager.default.fileExists(atPath: url.path + ".bad"))
    }
    check("cinema settings round-trip and are clamped on load") {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("luma-cinema-\(UUID()).json")
        let store = LayoutStore(url: url)
        try store.save(LayoutFile(panels: [], distance: 2, smoothFollow: false, lockedAxes: [],
                                  cinema: CinemaSettings(row: 9, screenScale: 1.2, lights: .lit, ipd: 0.06)))
        let c = store.load().cinema
        expectEqual(c?.row, 6); expectEqual(c?.lights, .lit); expectNear(c?.ipd ?? 0, 0.06)
    }
}
