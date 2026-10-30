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
        expectNear(l.viewer.z - l.screenCenter.z, 10); expectNear(l.screenCenter.x, 0); expectNear(l.screenWidth, 6)
    }
    check("rows step the screen from 7 to 13 m away") {
        func distance(_ row: Int) -> Double {
            let l = cinemaLayout(CinemaSettings(row: row), sourceAspect: nil)
            return l.viewer.z - l.screenCenter.z
        }
        expectNear(distance(0), 7); expectNear(distance(6), 13); expectNear(distance(-3), 7)
    }
    check("the screen sits near eye height and the floor below it, at any size") {
        for scale in [0.6, 1, 1.6] {
            for aspect in [0.9, 16.0 / 9, 2.39] {
                let l = cinemaLayout(CinemaSettings(screenScale: scale), sourceAspect: aspect)
                expect(abs(l.screenCenter.y - l.viewer.y) < 0.5)
                expect(l.floorY < l.screenBottom && l.floorY < l.viewer.y - 1)
                // The viewer is inside the screen's curve, so it bends towards them.
                expect(l.screenAxisZ - l.viewer.z < l.screenRadius)
            }
        }
    }
    check("settings clamp and ambience cycles") {
        let c = CinemaSettings(row: 12, screenScale: .nan, ambience: .full, ipd: 0.2).clamped
        expectEqual(c.row, 6); expectNear(c.screenScale, 1); expectNear(c.ipd, 0.075); expectEqual(c.ambience, .full)
        expectEqual(Ambience.off.next, .soft); expectEqual(Ambience.soft.next, .full); expectEqual(Ambience.full.next, .off)
    }
    check("a missing or silly source aspect falls back to 16:9") {
        expectNear(cinemaLayout(CinemaSettings(), sourceAspect: nil).screenHeight, 3.375)
        expectNear(cinemaLayout(CinemaSettings(), sourceAspect: 0).screenHeight, 3.375)
    }
}

func cinemaCommandChecks() {
    check("cinema mode is in the palette as 'cinema', 'movie' and 'vr'") {
        expectEqual(paletteMatches("cinema", in: Command.all).first, .toggleCinemaMode)
        expect(paletteMatches("movie", in: Command.all).contains(.toggleCinemaMode))
        expect(paletteMatches("vr", in: Command.all).contains(.toggleCinemaMode))
    }
    check("closer/farther step the distance, bigger/smaller scale the screen") {
        let s = CinemaSettings()
        expectEqual(cinemaAdjusted(s, by: .nudgeDistance(-0.25))?.row, 2)
        expectEqual(cinemaAdjusted(s, by: .nudgeDistance(0.25))?.row, 4)
        expectNear(cinemaAdjusted(s, by: .resizeSelected(1.1))!.screenScale, 1.1)
        expectNear(cinemaAdjusted(s, by: .nudgeIPD(0.001))!.ipd, 0.064)
        expectEqual(cinemaAdjusted(s, by: .cycleAmbience)?.ambience, .full)
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
                                  cinema: CinemaSettings(row: 9, screenScale: 1.2, ambience: .full, ipd: 0.06)))
        let c = store.load().cinema
        expectEqual(c?.row, 6); expectEqual(c?.ambience, .full); expectNear(c?.ipd ?? 0, 0.06)
    }
}

func cinemaScreenChangeChecks() {
    check("screen changes are ignored for a grace period after a mode switch") {
        expect(screenChangeIgnored(now: 1, until: 3)); expect(!screenChangeIgnored(now: 3.5, until: 3))
        expect(!screenChangeIgnored(now: 1, until: nil))
    }
}

func cinemaReviewFixChecks() {
    check("after a mode-switch blink the glasses window goes back onto the glasses, not to the preview") {
        expectEqual(glassesWindowAction(hasUsableScreen: true, onIt: false, frameMatches: false, switchingModes: false), .rehome)
        expectEqual(glassesWindowAction(hasUsableScreen: true, onIt: false, frameMatches: false, switchingModes: true), .rehome)
        expectEqual(glassesWindowAction(hasUsableScreen: true, onIt: true, frameMatches: false, switchingModes: false), .resize)
        expectEqual(glassesWindowAction(hasUsableScreen: true, onIt: true, frameMatches: true, switchingModes: false), .keep)
    }
    check("a missing glasses display only falls back to the preview outside a mode switch") {
        expectEqual(glassesWindowAction(hasUsableScreen: false, onIt: false, frameMatches: false, switchingModes: false), .fallBack)
        expectEqual(glassesWindowAction(hasUsableScreen: false, onIt: false, frameMatches: false, switchingModes: true), .keep)
    }
    check("glasses aren't declared lost while they switch display modes") {
        expect(!glassesLost(missedPolls: 2, sampleAge: 4, connectedFor: 10, switchingModes: true))
        expect(glassesLost(missedPolls: 2, sampleAge: 4, connectedFor: 10, switchingModes: false))
    }
    check("refresh rate picked in the cinema waits until the cinema ends") {
        expectEqual(rateToSend(.hz120, mode: .cinema), nil)
        expectEqual(rateToSend(.hz120, mode: .panels), .hz120)
    }
    check("tall or square sources fit the screen box instead of growing taller") {
        let square = cinemaLayout(CinemaSettings(), sourceAspect: 0.9)
        expectNear(square.screenHeight, 3.375); expectNear(square.screenWidth, 3.375 * 0.9)
        let wide = cinemaLayout(CinemaSettings(), sourceAspect: 2.39)
        expectNear(wide.screenWidth, 6); expectNear(wide.screenHeight, 6 / 2.39)
    }
}
