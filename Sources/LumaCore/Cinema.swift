import Foundation

/// How much of the screen's light spills into the space around it.
public enum Ambience: String, Codable, CaseIterable, Sendable {
    case off, soft, full

    public var next: Ambience {
        switch self {
        case .off: .soft
        case .soft: .full
        case .full: .off
        }
    }

    public var title: String { rawValue.capitalized }
}

/// Where the cinema's screen is: floating in the dark, or in a theater.
public enum CinemaEnvironment: String, Codable, CaseIterable, Sendable {
    case void, theater

    public var next: CinemaEnvironment { self == .void ? .theater : .void }
    public var title: String { rawValue.capitalized }
}

/// Everything about the cinema the user can change; saved with the layout.
public struct CinemaSettings: Codable, Equatable, Sendable {
    /// Seat rows (theater) or distance steps (void): row 0 is nearest the screen.
    public static let rows = 0...7
    public static let scale = 0.6...1.6

    public var row: Int
    public var screenScale: Double
    public var ambience: Ambience
    public var environment: CinemaEnvironment
    public var ipd: Double

    public init(row: Int = 5, screenScale: Double = 1, ambience: Ambience = .soft,
                environment: CinemaEnvironment = .theater, ipd: Double = IPD.standard) {
        self.row = row; self.screenScale = screenScale; self.ambience = ambience
        self.environment = environment; self.ipd = ipd
    }

    public var clamped: CinemaSettings {
        CinemaSettings(row: min(max(row, Self.rows.lowerBound), Self.rows.upperBound),
                       screenScale: screenScale.isFinite ? clamp(screenScale, Self.scale) : 1,
                       ambience: ambience, environment: environment,
                       ipd: ipd.isFinite ? clamp(ipd, IPD.range) : IPD.standard)
    }

    /// `lights` is how files saved by 0.2 (the box theater) stored it.
    enum CodingKeys: String, CodingKey { case row, screenScale, ambience, lights, environment, ipd }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let old: [String: Ambience] = ["dark": .off, "dim": .soft, "lit": .full]
        self.init(row: try c.decode(Int.self, forKey: .row),
                  screenScale: try c.decode(Double.self, forKey: .screenScale),
                  ambience: try c.decodeIfPresent(Ambience.self, forKey: .ambience)
                      ?? (try c.decodeIfPresent(String.self, forKey: .lights)).flatMap { old[$0] } ?? .soft,
                  environment: try c.decodeIfPresent(CinemaEnvironment.self, forKey: .environment) ?? .theater,
                  ipd: try c.decode(Double.self, forKey: .ipd))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(row, forKey: .row)
        try c.encode(screenScale, forKey: .screenScale)
        try c.encode(ambience, forKey: .ambience)
        try c.encode(environment, forKey: .environment)
        try c.encode(ipd, forKey: .ipd)
    }
}

/// An axis-aligned box.
public struct CinemaBox: Equatable, Sendable {
    public var center: Vec3
    public var size: Vec3
    public init(center: Vec3, size: Vec3) { self.center = center; self.size = size }

    public func contains(_ p: Vec3) -> Bool {
        abs(p.x - center.x) <= size.x / 2 && abs(p.y - center.y) <= size.y / 2 && abs(p.z - center.z) <= size.z / 2
    }
}

/// The cinema in metres: −z towards the screen, x right, y up. In the void the eyes are at
/// 1.2 m and the floor at or below 0 (lower for big screens); see `TheaterSpec` for the theater.
public struct CinemaLayout: Equatable, Sendable {
    public var viewer: Vec3
    public var screenCenter: Vec3
    public var screenWidth: Double
    public var screenHeight: Double
    /// The screen curves around a vertical axis this far behind it (behind the viewer too).
    public var screenRadius: Double
    /// The void's floor height (the theater's front floor is at 0).
    public var floorY: Double
    /// The space view rays can travel in, for the haze: endless in the void, the hall in the theater.
    public var room: CinemaBox
    /// The floor as a plane `floorNormal · p = floorOffset`; sloped along the theater's rows.
    public var floorNormal: Vec3
    public var floorOffset: Double
    /// Where the projector beam starts, in the theater.
    public var projector: Vec3?

    public var screenAxisZ: Double { screenCenter.z + screenRadius }
    /// Half the angle the screen spans around its axis.
    public var screenHalfAngle: Double { screenWidth / 2 / screenRadius }
    public var screenTop: Double { screenCenter.y + screenHeight / 2 }
    public var screenBottom: Double { screenCenter.y - screenHeight / 2 }
}

private enum Cinema {
    static let eyeHeight = 1.2, nearest = 5.0, rowStep = 1.0
    /// The screen's centre sits a little above the eyes; the floor this far under its bottom edge,
    /// but never higher than a seated eye height below the eyes.
    static let screenLift = 0.25, floorGap = 0.3
    static let screenWidth = 6.0, curve = 1.5
    /// The screen fits a 16:9 box this wide: wider sources get shorter, taller ones narrower.
    static let screenHeight = screenWidth * 9 / 16
}

public func cinemaLayout(_ s: CinemaSettings, sourceAspect: Double?) -> CinemaLayout {
    typealias C = Cinema
    let s = s.clamped
    let aspect = sourceAspect.flatMap { $0.isFinite && SceneLimits.aspect.contains($0) ? $0 : nil } ?? 16.0 / 9
    if s.environment == .theater { return theaterLayout(s, aspect: aspect) }
    let boxW = C.screenWidth * s.screenScale, boxH = C.screenHeight * s.screenScale
    let width = min(boxW, boxH * aspect), height = width / aspect
    let distance = C.nearest + Double(s.row) * C.rowStep
    let centerY = C.eyeHeight + C.screenLift
    let floorY = min(centerY - height / 2 - C.floorGap, 0)
    return CinemaLayout(viewer: Vec3(x: 0, y: C.eyeHeight, z: 0),
                        screenCenter: Vec3(x: 0, y: centerY, z: -distance),
                        screenWidth: width, screenHeight: height,
                        screenRadius: distance * C.curve,
                        floorY: floorY, room: CinemaBox(center: .zero, size: Vec3(x: 2000, y: 2000, z: 2000)),
                        floorNormal: Vec3(x: 0, y: 1, z: 0), floorOffset: floorY, projector: nil)
}

/// The cinema's answer to a command, or nil when the command isn't about the cinema.
/// Closer/Farther step the viewing distance; Bigger/Smaller scale the screen.
public func cinemaAdjusted(_ s: CinemaSettings, by c: Command) -> CinemaSettings? {
    var s = s
    switch c {
    case .nudgeDistance(let d): s.row += d < 0 ? -1 : 1
    case .resizeSelected(let f): s.screenScale *= f
    case .nudgeIPD(let d): s.ipd += d
    case .cycleAmbience: s.ambience = s.ambience.next
    case .cycleEnvironment: s.environment = s.environment.next
    default: return nil
    }
    return s.clamped
}

/// What the glasses show: LumaSpace's panels, a plain monitor for games, or the cinema.
public enum OutputMode: Equatable, Sendable { case panels, game, cinema }

/// Toggling the current mode goes back to panels; toggling another switches to it.
public func outputMode(after current: OutputMode, toggling m: OutputMode) -> OutputMode {
    current == m ? .panels : m
}

/// Switching display modes makes the glasses display blink; until `until` it counts as switching.
public func screenChangeIgnored(now: Double, until: Double?) -> Bool {
    until.map { now < $0 } ?? false
}

public enum GlassesWindowAction: Equatable, Sendable { case keep, resize, rehome, fallBack }

/// What to do with the glasses output window when displays change. While the glasses switch
/// display modes their display can vanish for a moment: wait instead of falling back to the preview.
public func glassesWindowAction(hasUsableScreen: Bool, onIt: Bool, frameMatches: Bool,
                                switchingModes: Bool) -> GlassesWindowAction {
    guard hasUsableScreen else { return switchingModes ? .keep : .fallBack }
    if !onIt { return .rehome }
    return frameMatches ? .keep : .resize
}

/// A refresh rate picked in the cinema is kept for when it ends; the glasses stay in 3D till then.
public func rateToSend(_ r: DisplayRate, mode: OutputMode) -> DisplayRate? {
    mode == .cinema ? nil : r
}
