import Foundation

/// How much light the theater has besides the glow from the screen.
public enum RoomLights: String, Codable, CaseIterable, Sendable {
    case dark, dim, lit

    public var ambient: Double {
        switch self {
        case .dark: 0
        case .dim: 0.08
        case .lit: 0.2
        }
    }

    public var next: RoomLights {
        switch self {
        case .dark: .dim
        case .dim: .lit
        case .lit: .dark
        }
    }

    public var title: String { rawValue.capitalized }
}

/// Everything about the cinema the user can change; saved with the layout.
public struct CinemaSettings: Codable, Equatable, Sendable {
    public static let rows = 0...6
    public static let scale = 0.6...1.6

    public var row: Int
    public var screenScale: Double
    public var lights: RoomLights
    public var ipd: Double

    public init(row: Int = 3, screenScale: Double = 1, lights: RoomLights = .dim, ipd: Double = IPD.standard) {
        self.row = row; self.screenScale = screenScale; self.lights = lights; self.ipd = ipd
    }

    public var clamped: CinemaSettings {
        CinemaSettings(row: min(max(row, Self.rows.lowerBound), Self.rows.upperBound),
                       screenScale: screenScale.isFinite ? clamp(screenScale, Self.scale) : 1,
                       lights: lights,
                       ipd: ipd.isFinite ? clamp(ipd, IPD.range) : IPD.standard)
    }
}

/// An axis-aligned box.
public struct CinemaBox: Equatable, Sendable {
    public var center: Vec3
    public var size: Vec3
    public init(center: Vec3, size: Vec3) { self.center = center; self.size = size }
}

/// A flat rectangle facing `normal`; `height` runs along `up`, `width` along `up × normal`.
public struct CinemaSurface: Equatable, Sendable {
    public var center: Vec3
    public var normal: Vec3
    public var up: Vec3
    public var width: Double
    public var height: Double
    public var albedo: Vec3
}

/// The theater in metres: −z towards the screen, x right, y up, y = 0 is the front floor.
public struct CinemaLayout: Equatable, Sendable {
    public var viewer: Vec3
    public var screenCenter: Vec3
    public var screenWidth: Double
    public var screenHeight: Double
    /// The screen curves around this radius, centred on the default row.
    public var screenRadius: Double
    public var room: CinemaBox
    public var surfaces: [CinemaSurface]
    public var seats: [CinemaBox]
    /// Stepped platforms the rows stand on (each row is 0.15 m higher than the one in front).
    public var risers: [CinemaBox]
}

private enum Theater {
    static let rowRise = 0.15, rowSpacing = 1.0, eyeHeight = 1.15
    static let seatsPerRow = 12, seatPitch = 0.55
    static let screenZ = -7.0, screenBottom = 1.0, screenWidth = 8.0, radius = 10.0
    static let wall = Vec3(x: 0.45, y: 0.40, z: 0.36)
    static let floor = Vec3(x: 0.18, y: 0.08, z: 0.08)
    static let ceiling = Vec3(x: 0.20, y: 0.20, z: 0.22)
}

public func cinemaLayout(_ s: CinemaSettings, sourceAspect: Double?) -> CinemaLayout {
    typealias T = Theater
    let s = s.clamped
    let aspect = sourceAspect.flatMap { $0.isFinite && SceneLimits.aspect.contains($0) ? $0 : nil } ?? 16.0 / 9
    let width = T.screenWidth * s.screenScale, height = width / aspect
    let screen = Vec3(x: 0, y: T.screenBottom + height / 2, z: T.screenZ)
    let viewer = Vec3(x: 0, y: T.rowRise * Double(s.row) + T.eyeHeight, z: Double(s.row) * T.rowSpacing)

    let halfW = width / 2 + 2, top = T.screenBottom + height + 2, back = T.screenZ - 0.5 + 16
    let room = CinemaBox(center: Vec3(x: 0, y: top / 2, z: (T.screenZ - 0.5 + back) / 2),
                         size: Vec3(x: halfW * 2, y: top, z: 16))
    let c = room.center, sz = room.size
    let up = Vec3(x: 0, y: 1, z: 0), forward = Vec3(x: 0, y: 0, z: -1)
    let surfaces = [
        CinemaSurface(center: Vec3(x: c.x, y: 0, z: c.z), normal: up, up: forward,
                      width: sz.x, height: sz.z, albedo: T.floor),
        CinemaSurface(center: Vec3(x: c.x, y: top, z: c.z), normal: up * -1, up: forward,
                      width: sz.x, height: sz.z, albedo: T.ceiling),
        CinemaSurface(center: Vec3(x: -halfW, y: c.y, z: c.z), normal: Vec3(x: 1, y: 0, z: 0), up: up,
                      width: sz.z, height: sz.y, albedo: T.wall),
        CinemaSurface(center: Vec3(x: halfW, y: c.y, z: c.z), normal: Vec3(x: -1, y: 0, z: 0), up: up,
                      width: sz.z, height: sz.y, albedo: T.wall),
        CinemaSurface(center: Vec3(x: c.x, y: c.y, z: back), normal: forward, up: up,
                      width: sz.x, height: sz.y, albedo: T.wall),
        CinemaSurface(center: Vec3(x: c.x, y: c.y, z: T.screenZ - 0.5), normal: forward * -1, up: up,
                      width: sz.x, height: sz.y, albedo: T.wall),
    ]

    var seats: [CinemaBox] = [], risers: [CinemaBox] = []
    for r in CinemaSettings.rows {
        let floor = T.rowRise * Double(r), z = Double(r) * T.rowSpacing
        for i in 0..<T.seatsPerRow {
            let x = (Double(i) - Double(T.seatsPerRow - 1) / 2) * T.seatPitch
            seats.append(CinemaBox(center: Vec3(x: x, y: floor + 0.45, z: z + 0.25), size: Vec3(x: 0.5, y: 0.9, z: 0.5)))
        }
        if r > 0 {
            risers.append(CinemaBox(center: Vec3(x: 0, y: floor / 2, z: z), size: Vec3(x: halfW * 2, y: floor, z: T.rowSpacing)))
        }
    }
    return CinemaLayout(viewer: viewer, screenCenter: screen, screenWidth: width, screenHeight: height,
                        screenRadius: T.radius, room: room, surfaces: surfaces, seats: seats, risers: risers)
}
