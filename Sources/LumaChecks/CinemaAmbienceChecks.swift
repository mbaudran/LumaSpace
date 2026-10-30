import Foundation
import LumaCore

func cinemaAmbienceChecks() {
    check("layouts saved with the box theater's room lights load as ambience") {
        for (lights, ambience) in [("dark", Ambience.off), ("dim", .soft), ("lit", .full)] {
            let json = #"{"row":2,"screenScale":1,"lights":"\#(lights)","ipd":0.063}"#
            let s = try JSONDecoder().decode(CinemaSettings.self, from: Data(json.utf8))
            expectEqual(s.ambience, ambience); expectEqual(s.row, 2)
        }
        let saved = String(decoding: try JSONEncoder().encode(CinemaSettings(ambience: .off)), as: UTF8.self)
        expect(saved.contains(#""ambience":"off""#)); expect(!saved.contains("lights"))
    }
    check("ambience Off keeps only a faint reflection; Soft is gentler than Full") {
        let off = Ambience.off.strength, soft = Ambience.soft.strength, full = Ambience.full.strength
        expectEqual([off.halo, off.haze, off.dust, off.bloom], [0, 0, 0, 0]); expect(off.reflection > 0)
        for (s, f) in zip([soft.halo, soft.haze, soft.reflection, soft.dust, soft.bloom],
                          [full.halo, full.haze, full.reflection, full.dust, full.bloom]) {
            expect(s > 0 && s < f)
        }
        expect(off.reflection < soft.reflection)
    }
    check("the glow catches up ~63% in 0.3 s, whatever the frame rate") {
        expectNear(glowBlend(dt: 0.3), 1 - exp(-1))
        let half = glowBlend(dt: 0.15)
        expectNear(1 - (1 - half) * (1 - half), glowBlend(dt: 0.3))
        let n = 27, step = glowBlend(dt: 0.3 / Double(n))
        expectNear(1 - pow(1 - step, Double(n)), glowBlend(dt: 0.3), tol: 1e-9)
        expectEqual(glowBlend(dt: 0), 0); expectEqual(glowBlend(dt: .nan), 0); expectEqual(glowBlend(dt: -1), 0)
    }
    check("cinema fades in from black over 1.2 s") {
        expectEqual(cinemaFade(elapsed: 0), 0); expectEqual(cinemaFade(elapsed: 1.2), 1); expectEqual(cinemaFade(elapsed: 50), 1)
        expectEqual(cinemaFade(elapsed: -1), 0)
        let samples = stride(from: 0.0, through: 1.2, by: 0.1).map { cinemaFade(elapsed: $0) }
        expect(zip(samples, samples.dropFirst()).allSatisfy { $0 < $1 })
    }
}

func cinemaGeometryChecks() {
    let l = cinemaLayout(CinemaSettings(), sourceAspect: 16.0 / 9)
    check("16 screen lights lie on the curved screen and face the viewer") {
        let lights = screenLights(l)
        expectEqual(lights.count, 16)
        for li in lights {
            let r = (li.position.x * li.position.x + (li.position.z - l.screenAxisZ) * (li.position.z - l.screenAxisZ)).squareRoot()
            expectNear(r, l.screenRadius, tol: 1e-9)
            expect(li.position.y < l.screenTop && li.position.y > l.screenBottom)
            expectNear(li.normal.length, 1, tol: 1e-9)
            expect(li.normal.dot(l.viewer - li.position) > 0)
        }
        expect(lights[0].position.x < lights[7].position.x); expect(lights[0].position.y > lights[8].position.y)
    }
    check("a ray from the viewer hits the screen where the screen is") {
        let d = (l.screenCenter - l.viewer) * (1 / (l.screenCenter - l.viewer).length)
        let centre = screenHit(origin: l.viewer, dir: d, l)
        expectNear(centre?.u ?? -1, 0.5, tol: 1e-9); expectNear(centre?.v ?? -1, 0.5, tol: 1e-9)
        expectNear(centre?.t ?? -1, (l.screenCenter - l.viewer).length, tol: 1e-9)
        for (u, v) in [(0.2, 0.7), (0.95, 0.05), (0.01, 0.99)] {
            let p = screenPoint(u: u, v: v, l), to = p - l.viewer
            let hit = screenHit(origin: l.viewer, dir: to * (1 / to.length), l)
            expectNear(hit?.u ?? -1, u, tol: 1e-9); expectNear(hit?.v ?? -1, v, tol: 1e-9)
        }
    }
    check("rays that pass the screen, point away or start outside its curve miss") {
        expectEqual(screenHit(origin: l.viewer, dir: Vec3(x: 0, y: 1, z: 0), l), nil)
        expectEqual(screenHit(origin: l.viewer, dir: Vec3(x: 0, y: 0, z: 1), l), nil)
        expectEqual(screenHit(origin: l.viewer, dir: Vec3(x: 1, y: 0, z: 0), l), nil)
        expectEqual(screenHit(origin: Vec3(x: 0, y: l.viewer.y, z: -100), dir: Vec3(x: 0, y: 0, z: 1), l), nil)
    }
    check("the floor mirrors the screen: its reflection is the screen seen from below the floor") {
        let eye = l.viewer, mirrored = Vec3(x: eye.x, y: 2 * l.floorY - eye.y, z: eye.z)
        for p in [Vec3(x: 0, y: l.floorY, z: -4), Vec3(x: 1.5, y: l.floorY, z: -5), Vec3(x: -0.5, y: l.floorY, z: -6)] {
            let r = floorReflection(eye: eye, point: p, l)
            let d = p - mirrored
            let direct = screenHit(origin: mirrored, dir: d * (1 / d.length), l)
            expect(r != nil)
            expectNear(r?.u ?? -1, direct?.u ?? -2, tol: 1e-9); expectNear(r?.v ?? -1, direct?.v ?? -2, tol: 1e-9)
        }
        // Right under the screen the floor reflects the gap below it; near the viewer the reflected
        // ray rises too steeply to reach the screen.
        expectEqual(floorReflection(eye: eye, point: Vec3(x: 0, y: l.floorY, z: -9), l), nil)
        expectEqual(floorReflection(eye: eye, point: Vec3(x: 0, y: l.floorY, z: -0.5), l), nil)
        expectEqual(floorReflection(eye: Vec3(x: 0, y: l.floorY - 1, z: 0), point: Vec3(x: 0, y: l.floorY, z: -8), l), nil)
    }
    check("haze starts at 0, grows along the ray, saturates and is brighter near the light") {
        let o = l.viewer, d = Vec3(x: 0, y: 0, z: -1), light = Vec3(x: 0.5, y: l.viewer.y, z: -6)
        expectEqual(hazeIntegral(origin: o, dir: d, length: 0, light: light), 0)
        let lengths = [1.0, 3, 6, 9, 20, 200]
        let values = lengths.map { hazeIntegral(origin: o, dir: d, length: $0, light: light) }
        expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        let h = (0.25 + hazeSoftening).squareRoot()
        expect(values.last! < Double.pi / h)
        let far = Vec3(x: 3, y: l.viewer.y, z: -6)
        expect(hazeIntegral(origin: o, dir: d, length: 20, light: far) < values[4])
    }
    check("dust motes stay in their box, move, and are the same every run") {
        let box = dustBox(l)
        expect(box.size.x > 0 && box.size.y > 0 && box.size.z > 0)
        expect(box.center.z < l.viewer.z && box.center.z > l.screenCenter.z)
        for t in [0.0, 7.5, 600, 1e5] {
            for i in stride(from: 0, to: dustCount, by: 37) { expect(box.contains(dustMote(i, time: t, in: box))) }
        }
        expectEqual(dustMote(5, time: 3, in: box), dustMote(5, time: 3, in: box))
        expect((dustMote(5, time: 0, in: box) - dustMote(5, time: 60, in: box)).length > 0.1)
        expect((dustMote(5, time: 0, in: box) - dustMote(6, time: 0, in: box)).length > 0.1)
    }
}

@MainActor
func lensTintChecks() {
    check("simulated glasses darken and restore the lens tint") {
        let g = SimulatedGlasses(reason: "test")
        expectEqual(g.lensTint(), false)
        g.setLensTint(true); expectEqual(g.lensTint(), true)
        g.setLensTint(false); expectEqual(g.tintCalls, [true, false])
    }
    check("glasses without a tint can't report one") {
        let g = SimulatedGlasses(reason: "test")
        g.tint = nil
        g.setLensTint(true)
        expectEqual(g.lensTint(), nil)
    }
    check("the palette finds Ambience as 'ambience' and 'lights'") {
        expectEqual(paletteMatches("ambience", in: Command.all).first, .cycleAmbience)
        expect(paletteMatches("lights", in: Command.all).contains(.cycleAmbience))
    }
}
