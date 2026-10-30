import Foundation

/// The theater (Dolby Cinema style) in metres, in the `CinemaLayout` frame: −z towards the screen,
/// y up, the front floor at y = 0. Row r's seats stand on a riser `rowRise·r` high, centred at
/// z = `rowSpacing·r`; aisles run down both sides of the seats with two steps per row.
public enum TheaterSpec {
    public static let rows = 8, seatsPerRow = 9
    public static let rowSpacing = 1.1, rowRise = 0.4, seatPitch = 0.8
    /// Seated in a recliner: eyes this high above the riser and this far behind the seat's centre.
    public static let eyeHeight = 1.1, eyeBack = 0.2
    public static let screenZ = -6.0, screenBottom = 0.9, screenWidth = 7.5, screenRadius = 30.0
    public static let halfWidth = 5.6, ceiling = 8.5, frontWall = -6.4
    public static let aisleWidth = 1.3
    /// The acoustic fins on the side walls, and the LED strips in the gaps between them.
    public static let finSpacing = 1.8, finStart = -5.2
    public static var backWall: Double { Double(rows - 1) * rowSpacing + 1.6 }
    public static var seatBlockHalf: Double { Double(seatsPerRow) / 2 * seatPitch }
    public static var maxScreenWidth: Double { 2 * halfWidth - 1 }
    public static var projector: Vec3 { Vec3(x: 0, y: ceiling - 1.5, z: backWall - 0.05) }
}

func theaterLayout(_ s: CinemaSettings, aspect: Double) -> CinemaLayout {
    typealias T = TheaterSpec
    let boxW = min(T.screenWidth * s.screenScale, T.maxScreenWidth)
    let boxH = min(boxW * 9 / 16, T.ceiling - T.screenBottom - 1.5)
    let width = min(boxW, boxH * aspect), height = width / aspect
    let row = Double(s.row)
    // The rows' riser edges, as one slope for the haze.
    let slope = T.rowRise / T.rowSpacing, len = (1 + slope * slope).squareRoot()
    let z0 = -T.rowSpacing / 2
    return CinemaLayout(viewer: Vec3(x: 0, y: T.rowRise * row + T.eyeHeight, z: T.rowSpacing * row + T.eyeBack),
                        screenCenter: Vec3(x: 0, y: T.screenBottom + height / 2, z: T.screenZ),
                        screenWidth: width, screenHeight: height, screenRadius: T.screenRadius, floorY: 0,
                        room: CinemaBox(center: Vec3(x: 0, y: T.ceiling / 2, z: (T.frontWall + T.backWall) / 2),
                                        size: Vec3(x: 2 * T.halfWidth, y: T.ceiling, z: T.backWall - T.frontWall)),
                        floorNormal: Vec3(x: 0, y: 1 / len, z: -slope / len), floorOffset: -slope * z0 / len,
                        projector: T.projector)
}

/// Surfaces of the theater; the shaders give each its texture and finish (same raw values).
public enum TheaterMaterial: Int, CaseIterable, Sendable {
    case leather, wallFabric, carpet, ceiling, masking, trim, ledWarm, ledStep, projectorPort
}

public struct TheaterVertex: Equatable, Sendable {
    public var position: Vec3
    public var normal: Vec3
    /// Texture coordinates in metres; each material tiles them at its own scale.
    public var u, v: Double
    public var material: TheaterMaterial
    /// Baked ambient occlusion, 0 (dark) … 1.
    public var ao: Double
}

/// Triangles of a box with rounded edges, `segments` quads across each face, tilted back by
/// `tilt` radians around x (its top moves towards +z). `ao` darkens by local height.
func roundedBox(center c: Vec3, size: Vec3, radius: Double, tilt: Double = 0, segments n: Int = 6,
                material: TheaterMaterial, ao: (Double) -> Double = { _ in 1 }) -> [TheaterVertex] {
    let h = size * 0.5, r = min(radius, min(h.x, min(h.y, h.z)) * 0.999)
    let inner = Vec3(x: h.x - r, y: h.y - r, z: h.z - r)
    let ct = cos(tilt), st = sin(tilt)
    func rotate(_ p: Vec3) -> Vec3 { Vec3(x: p.x, y: p.y * ct - p.z * st, z: p.y * st + p.z * ct) }
    func vertex(_ g: Vec3, _ uv: (Double, Double)) -> TheaterVertex {
        let q = Vec3(x: clamp(g.x, -inner.x...inner.x), y: clamp(g.y, -inner.y...inner.y), z: clamp(g.z, -inner.z...inner.z))
        let d = g - q, len = d.length
        let n = len > 1e-9 ? d * (1 / len) : Vec3(x: 0, y: 1, z: 0)
        let p = q + n * r
        return TheaterVertex(position: c + rotate(p), normal: rotate(n), u: uv.0, v: uv.1, material: material, ao: ao(p.y + h.y))
    }
    // Each face: an axis it faces along, and the two axes its grid spans.
    let faces: [(normal: Vec3, a: Vec3, b: Vec3)] = [
        (Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: -1), Vec3(x: 0, y: 1, z: 0)),
        (Vec3(x: -1, y: 0, z: 0), Vec3(x: 0, y: 0, z: 1), Vec3(x: 0, y: 1, z: 0)),
        (Vec3(x: 0, y: 1, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: -1)),
        (Vec3(x: 0, y: -1, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: 1)),
        (Vec3(x: 0, y: 0, z: 1), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0)),
        (Vec3(x: 0, y: 0, z: -1), Vec3(x: -1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0)),
    ]
    func scaled(_ v: Vec3) -> Vec3 { Vec3(x: v.x * h.x, y: v.y * h.y, z: v.z * h.z) }
    func extent(_ v: Vec3) -> Double { abs(v.x) * h.x + abs(v.y) * h.y + abs(v.z) * h.z }
    var out: [TheaterVertex] = []
    for f in faces {
        func g(_ i: Int, _ j: Int) -> TheaterVertex {
            let s = Double(i) / Double(n) * 2 - 1, t = Double(j) / Double(n) * 2 - 1
            return vertex(scaled(f.normal) + scaled(f.a) * s + scaled(f.b) * t, (s * extent(f.a), t * extent(f.b)))
        }
        for i in 0..<n {
            for j in 0..<n {
                let a = g(i, j), b = g(i + 1, j), cc = g(i + 1, j + 1), d = g(i, j + 1)
                out += [a, b, cc, a, cc, d]
            }
        }
    }
    return out
}

/// A flat rectangle: `right` and `up` are half extents; it faces `right × up`.
func theaterQuad(_ c: Vec3, right: Vec3, up: Vec3, _ m: TheaterMaterial) -> [TheaterVertex] {
    let n0 = right.cross(up), n = n0 * (1 / n0.length)
    let rl = right.length, ul = up.length
    func v(_ s: Double, _ t: Double) -> TheaterVertex {
        TheaterVertex(position: c + right * s + up * t, normal: n, u: s * rl, v: t * ul, material: m, ao: 1)
    }
    let a = v(-1, -1), b = v(1, -1), d = v(1, 1), e = v(-1, 1)
    return [a, b, d, a, d, e]
}

/// A plain box (flat faces), for steps, fins and strips.
func theaterBox(_ c: Vec3, size: Vec3, _ m: TheaterMaterial) -> [TheaterVertex] {
    let x = Vec3(x: size.x / 2, y: 0, z: 0), y = Vec3(x: 0, y: size.y / 2, z: 0), z = Vec3(x: 0, y: 0, z: size.z / 2)
    return theaterQuad(c + x, right: z * -1, up: y, m) + theaterQuad(c - x, right: z, up: y, m)
        + theaterQuad(c + y, right: x, up: z * -1, m) + theaterQuad(c - y, right: x, up: z, m)
        + theaterQuad(c + z, right: x, up: y, m) + theaterQuad(c - z, right: x * -1, up: y, m)
}

/// One recliner without armrests, standing on y = 0, facing −z.
public func theaterSeatMesh() -> [TheaterVertex] {
    let ao: (Double) -> Double = { y in 0.45 + 0.55 * min(max(y / 1.0, 0), 1) }
    let tilt = 14 * Double.pi / 180
    return roundedBox(center: Vec3(x: 0, y: 0.15, z: 0.02), size: Vec3(x: 0.6, y: 0.3, z: 0.7), radius: 0.04,
                      material: .leather, ao: { y in ao(y) * 0.8 })
        + roundedBox(center: Vec3(x: 0, y: 0.4, z: -0.03), size: Vec3(x: 0.58, y: 0.2, z: 0.64), radius: 0.08,
                     material: .leather, ao: { y in ao(y + 0.3) })
        + roundedBox(center: Vec3(x: 0, y: 0.76, z: 0.33), size: Vec3(x: 0.58, y: 0.66, z: 0.2), radius: 0.09, tilt: tilt,
                     material: .leather, ao: { y in ao(y + 0.45) })
        + roundedBox(center: Vec3(x: 0, y: 1.1, z: 0.42), size: Vec3(x: 0.5, y: 0.24, z: 0.17), radius: 0.08, tilt: tilt,
                     material: .leather)
}

/// An armrest panel between two seats (and at each end of a row), down to the floor.
public func theaterArmMesh() -> [TheaterVertex] {
    roundedBox(center: Vec3(x: 0, y: 0.33, z: 0.02), size: Vec3(x: 0.16, y: 0.66, z: 0.76), radius: 0.05,
               material: .leather, ao: { y in 0.4 + 0.6 * min(max(y / 0.66, 0), 1) })
        + roundedBox(center: Vec3(x: 0, y: 0.665, z: -0.22), size: Vec3(x: 0.12, y: 0.012, z: 0.22), radius: 0.005,
                     segments: 1, material: .trim)
}

/// Where each seat stands (floor point under its centre), row by row from the front left.
public func theaterSeatPositions() -> [Vec3] {
    typealias T = TheaterSpec
    return (0..<T.rows).flatMap { r in
        (0..<T.seatsPerRow).map { i in
            Vec3(x: (Double(i) - Double(T.seatsPerRow - 1) / 2) * T.seatPitch, y: T.rowRise * Double(r), z: T.rowSpacing * Double(r))
        }
    }
}

/// Where each armrest stands: between seats and at both ends of every row.
public func theaterArmPositions() -> [Vec3] {
    typealias T = TheaterSpec
    return (0..<T.rows).flatMap { r in
        (0...T.seatsPerRow).map { i in
            Vec3(x: (Double(i) - Double(T.seatsPerRow) / 2) * T.seatPitch, y: T.rowRise * Double(r), z: T.rowSpacing * Double(r))
        }
    }
}

/// The hall: floor and risers, aisle steps with LED nosings, finned side walls with LED strips,
/// ceiling baffles, the black front wall and the projector port.
public func theaterRoomMesh() -> [TheaterVertex] {
    typealias T = TheaterSpec
    let w = T.halfWidth, up = Vec3(x: 0, y: 1, z: 0)
    let right = Vec3(x: 1, y: 0, z: 0), back = Vec3(x: 0, y: 0, z: 1)
    var m: [TheaterVertex] = []
    func rise(_ r: Int) -> Double { T.rowRise * Double(r) }
    func edge(_ r: Int) -> Double { (Double(r) - 0.5) * T.rowSpacing }  // where row r's riser starts

    // Front floor, then each row's riser: its top and the face towards the screen.
    m += theaterQuad(Vec3(x: 0, y: 0, z: (T.frontWall + edge(1)) / 2), right: right * w,
                     up: back * -((edge(1) - T.frontWall) / 2), .carpet)
    for r in 1..<T.rows {
        let far = r == T.rows - 1 ? T.backWall : edge(r + 1)
        m += theaterQuad(Vec3(x: 0, y: rise(r), z: (edge(r) + far) / 2), right: right * w, up: back * -((far - edge(r)) / 2), .carpet)
        m += theaterQuad(Vec3(x: 0, y: (rise(r - 1) + rise(r)) / 2, z: edge(r)), right: right * -w,
                         up: up * (T.rowRise / 2), .carpet)
        // The aisles get a half step in front of each riser, and LED nosings on both steps.
        for side in [-1.0, 1.0] {
            let x = side * (T.seatBlockHalf + 0.1 + T.aisleWidth / 2)
            m += theaterBox(Vec3(x: x, y: rise(r - 1) + T.rowRise / 4, z: edge(r) - 0.22),
                            size: Vec3(x: T.aisleWidth, y: T.rowRise / 2, z: 0.44), .carpet)
            for (y, z) in [(rise(r - 1) + T.rowRise / 2, edge(r) - 0.44), (rise(r), edge(r))] {
                m += theaterBox(Vec3(x: x, y: y - 0.012, z: z - 0.012), size: Vec3(x: T.aisleWidth - 0.1, y: 0.02, z: 0.02), .ledStep)
            }
        }
    }
    // Side walls: dark backing, angled fabric fins, warm LED strips in the gaps.
    let length = T.backWall - T.frontWall, mid = (T.backWall + T.frontWall) / 2
    for side in [-1.0, 1.0] {
        m += theaterQuad(Vec3(x: side * w, y: T.ceiling / 2, z: mid), right: back * (side * length / 2),
                         up: up * (T.ceiling / 2), .ceiling)
        var z = T.finStart
        while z + T.finSpacing / 2 < T.backWall {
            let fin = roundedBox(center: Vec3(x: side * (w - 0.18), y: T.ceiling / 2 + 0.2, z: z + T.finSpacing / 2),
                                 size: Vec3(x: 0.1, y: T.ceiling - 1.6, z: T.finSpacing - 0.25), radius: 0.03,
                                 segments: 2, material: .wallFabric)
            // Turn each fin a little towards the screen.
            let a = side * 8 * Double.pi / 180, cz = z + T.finSpacing / 2, cx = side * (w - 0.18)
            m += fin.map { v in
                var v = v
                func turn(_ p: Vec3, about o: Vec3) -> Vec3 {
                    let dx = p.x - o.x, dz = p.z - o.z
                    return Vec3(x: o.x + dx * cos(a) + dz * sin(a), y: p.y, z: o.z - dx * sin(a) + dz * cos(a))
                }
                v.position = turn(v.position, about: Vec3(x: cx, y: 0, z: cz))
                v.normal = turn(v.normal, about: .zero)
                return v
            }
            m += theaterBox(Vec3(x: side * (w - 0.04), y: T.ceiling / 2 + 0.2, z: z), size: Vec3(x: 0.03, y: T.ceiling - 2.4, z: 0.04), .ledWarm)
            z += T.finSpacing
        }
    }
    // Ceiling and acoustic baffles across it.
    m += theaterQuad(Vec3(x: 0, y: T.ceiling, z: mid), right: right * w, up: back * (length / 2), .ceiling)
    var z = T.frontWall + 2
    while z < T.backWall - 1 {
        m += theaterBox(Vec3(x: 0, y: T.ceiling - 0.35, z: z), size: Vec3(x: 2 * w - 0.4, y: 0.7, z: 0.12), .ceiling)
        z += 2.2
    }
    // Back wall with the projector port, and the black front wall around the screen.
    m += theaterQuad(Vec3(x: 0, y: T.ceiling / 2, z: T.backWall), right: right * -w, up: up * (T.ceiling / 2), .wallFabric)
    m += theaterQuad(T.projector, right: right * -0.35, up: up * 0.22, .projectorPort)
    m += theaterQuad(Vec3(x: 0, y: T.ceiling / 2, z: T.frontWall), right: right * w, up: up * (T.ceiling / 2), .masking)
    return m
}

/// How bright the house lights are meant to be: up for the first seconds after entering, then
/// the level the ambience asks for (the renderer eases towards it).
public func houseLightTarget(_ level: Double, elapsed: Double) -> Double {
    elapsed < 3 ? 1 : level
}
