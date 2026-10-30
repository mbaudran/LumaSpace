import Foundation
import LumaCore

func theaterChecks() {
    typealias T = TheaterSpec
    func layout(row: Int = 5, scale: Double = 1, aspect: Double = 16.0 / 9) -> CinemaLayout {
        cinemaLayout(CinemaSettings(row: row, screenScale: scale, environment: .theater), sourceAspect: aspect)
    }
    let seat = theaterSeatMesh()

    check("the theater is the default environment; older layouts open in it, the void stays saved") {
        expectEqual(CinemaSettings().environment, .theater)
        let old = try JSONDecoder().decode(CinemaSettings.self, from: Data(#"{"row":2,"screenScale":1,"ambience":"soft","ipd":0.063}"#.utf8))
        expectEqual(old.environment, .theater)
        let saved = try JSONEncoder().encode(CinemaSettings(environment: .void))
        expectEqual(try JSONDecoder().decode(CinemaSettings.self, from: saved).environment, .void)
        expectEqual(CinemaEnvironment.void.next, .theater); expectEqual(CinemaEnvironment.theater.next, .void)
        expectEqual(cinemaAdjusted(CinemaSettings(), by: .cycleEnvironment)?.environment, .void)
        expectEqual(paletteMatches("environment", in: Command.all).first, .cycleEnvironment)
    }
    check("each row puts you in the middle seat, eyes above it, inside the hall") {
        let seats = theaterSeatPositions()
        expectEqual(seats.count, T.rows * T.seatsPerRow)
        for r in CinemaSettings.rows {
            let l = layout(row: r)
            expect(l.room.contains(l.viewer))
            let mine = seats.min { ($0 - l.viewer).length < ($1 - l.viewer).length }!
            expectNear(mine.x, 0); expectNear(l.viewer.y - mine.y, T.eyeHeight)
        }
        expect(layout(row: 7).viewer.z - layout(row: 0).viewer.z > 7)
    }
    check("every row sees the whole screen over the seats in front") {
        let top = seat.max { $0.position.y < $1.position.y }!.position
        for r in 1..<T.rows {
            let l = layout(row: r)
            let bottom = Vec3(x: 0, y: l.screenBottom, z: l.screenCenter.z)
            // Where the line from the eyes to the screen's bottom edge passes the seat in front.
            let front = Vec3(x: 0, y: T.rowRise * Double(r - 1), z: T.rowSpacing * Double(r - 1)) + top
            let t = (l.viewer.z - front.z) / (l.viewer.z - bottom.z)
            let lineY = l.viewer.y + (bottom.y - l.viewer.y) * t
            expect(lineY > front.y, "row \(r): sight line \(lineY) under seat top \(front.y)")
        }
    }
    check("the screen fits the front wall at any size, above the floor and below the ceiling") {
        for scale in [0.6, 1, 1.6] {
            for aspect in [0.9, 16.0 / 9, 2.39] {
                let l = layout(scale: scale, aspect: aspect)
                expect(l.screenWidth <= T.maxScreenWidth + 1e-9 && l.screenBottom > 0 && l.screenTop < T.ceiling)
                expect(l.screenCenter.z > T.frontWall && l.room.contains(l.screenCenter))
            }
        }
    }
    check("the sloped floor for the haze stays under every seat and the projector is in the hall") {
        let l = layout()
        for p in theaterSeatPositions() { expect(l.floorNormal.dot(p) <= l.floorOffset + 0.25) }
        expect(l.floorNormal.dot(l.viewer) > l.floorOffset)
        expect(l.projector.map { l.room.contains($0) } ?? false)
        expectEqual(cinemaLayout(CinemaSettings(environment: .void), sourceAspect: nil).projector, nil)
    }
    check("meshes: unit normals, AO in range, seats and armrests don't overlap their neighbours") {
        let room = theaterRoomMesh(), arm = theaterArmMesh()
        for v in seat + arm + room {
            expectNear(v.normal.length, 1, tol: 1e-6)
            expect(v.ao > 0 && v.ao <= 1)
        }
        expectEqual(room.count % 3, 0); expectEqual(seat.count % 3, 0)
        let seatHalf = seat.map { abs($0.position.x) }.max()!, armHalf = arm.map { abs($0.position.x) }.max()!
        expect(seatHalf + armHalf < T.seatPitch / 2 + 0.02)
        var hall = layout().room
        hall.size = hall.size + Vec3(x: 0.02, y: 0.02, z: 0.02)
        expect(room.allSatisfy { hall.contains($0.position) })
    }
    check("house lights stay up for the first seconds, then follow the ambience") {
        expectEqual(houseLightTarget(0.25, elapsed: 0), 1); expectEqual(houseLightTarget(0.25, elapsed: 5), 0.25)
        let off = Ambience.off.strength(in: .theater), soft = Ambience.soft.strength(in: .theater)
        let full = Ambience.full.strength(in: .theater)
        expectEqual(off.house, 0); expectEqual(off.beam, 0); expectEqual(off.haze, 0)
        expect(soft.house < full.house && soft.beam < full.beam && soft.haze < full.haze)
        expectEqual([full.halo, full.reflection], [0, 0])  // no halo or glossy floor in a theater
        expectEqual(Ambience.soft.strength(in: .void), Ambience.soft.strength)
    }
}
