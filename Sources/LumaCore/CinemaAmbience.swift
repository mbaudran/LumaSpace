import Foundation

// The maths behind the cinema's glow. `CinemaShaders.swift` mirrors these functions on the GPU;
// they live here so they can be checked without Metal.

/// How strongly each effect is drawn, 0...1.
public struct AmbienceStrength: Equatable, Sendable {
    public var halo, haze, reflection, dust, bloom: Double
}

extension Ambience {
    public var strength: AmbienceStrength {
        switch self {
        case .off: AmbienceStrength(halo: 0, haze: 0, reflection: 0.3, dust: 0, bloom: 0)
        case .soft: AmbienceStrength(halo: 0.55, haze: 0.5, reflection: 0.7, dust: 0.5, bloom: 0.5)
        case .full: AmbienceStrength(halo: 1, haze: 1, reflection: 1, dust: 1, bloom: 1)
        }
    }
}

/// How far the glow moves towards the current picture in a frame `dt` seconds long: exponential
/// smoothing with time constant `tau`, the same over a second at any frame rate.
public func glowBlend(dt: Double, tau: Double = 0.3) -> Double {
    guard dt.isFinite, dt > 0 else { return 0 }
    return 1 - exp(-min(dt, 1) / tau)
}

/// Brightness while cinema mode fades in from black: 0 at the start, 1 after `duration`.
public func cinemaFade(elapsed: Double, duration: Double = 1.2) -> Double {
    let t = clamp(elapsed.isFinite ? elapsed / duration : 1, 0...1)
    return t * t * (3 - 2 * t)
}

/// The point of the curved screen at `u` (0 left … 1 right) and `v` (0 top … 1 bottom).
public func screenPoint(u: Double, v: Double, _ l: CinemaLayout) -> Vec3 {
    let a = (u * 2 - 1) * l.screenHalfAngle
    return Vec3(x: l.screenRadius * sin(a), y: l.screenTop - v * l.screenHeight, z: l.screenAxisZ - l.screenRadius * cos(a))
}

/// A sample of the screen's light: a point on it, facing the viewer's side, glowing with the
/// picture's colour around (u, v).
public struct CinemaLight: Equatable, Sendable {
    public var position: Vec3
    public var normal: Vec3
    public var u, v: Double
}

public let cinemaLightColumns = 8, cinemaLightRows = 2

/// The screen as 8 × 2 point lights, row by row from the top left.
public func screenLights(_ l: CinemaLayout) -> [CinemaLight] {
    (0..<cinemaLightRows).flatMap { r in
        (0..<cinemaLightColumns).map { c in
            let u = (Double(c) + 0.5) / Double(cinemaLightColumns), v = (Double(r) + 0.5) / Double(cinemaLightRows)
            let a = (u * 2 - 1) * l.screenHalfAngle
            return CinemaLight(position: screenPoint(u: u, v: v, l), normal: Vec3(x: -sin(a), y: 0, z: cos(a)), u: u, v: v)
        }
    }
}

public struct ScreenHit: Equatable, Sendable {
    public var u, v: Double
    /// Distance along the ray.
    public var t: Double
}

/// Where a ray starting inside the screen's cylinder hits the screen, or nil if it misses.
/// `dir` must be normalised.
public func screenHit(origin o: Vec3, dir d: Vec3, _ l: CinemaLayout) -> ScreenHit? {
    let ox = o.x, oz = o.z - l.screenAxisZ
    let a = d.x * d.x + d.z * d.z, b = ox * d.x + oz * d.z, c = ox * ox + oz * oz - l.screenRadius * l.screenRadius
    guard a > 1e-9, c < 0 else { return nil }
    let t = (-b + (b * b - a * c).squareRoot()) / a  // from inside, the far root is the only one ahead
    let p = o + d * t
    let u = (atan2(p.x, l.screenAxisZ - p.z) / l.screenHalfAngle + 1) / 2
    let v = (l.screenTop - p.y) / l.screenHeight
    guard t > 0, (0...1).contains(u), (0...1).contains(v) else { return nil }
    return ScreenHit(u: u, v: v, t: t)
}

/// What the floor at `point` reflects of the screen when seen from `eye`.
public func floorReflection(eye: Vec3, point: Vec3, _ l: CinemaLayout) -> ScreenHit? {
    let d = point - eye
    guard d.length > 0, d.y < 0 else { return nil }  // only floor seen from above reflects
    let n = d * (1 / d.length)
    return screenHit(origin: point, dir: Vec3(x: n.x, y: -n.y, z: n.z), l)
}

/// Softening (m²) that keeps the haze finite for rays passing through a light.
public let hazeSoftening = 0.25

/// Light scattered towards the eye along `length` metres of a ray, from a unit point light:
/// ∫ dt / (|o + t·d − light|² + softening), in closed form.
public func hazeIntegral(origin o: Vec3, dir d: Vec3, length: Double, light: Vec3) -> Double {
    let w = o - light
    let b = d.dot(w), h = (max(w.dot(w) - b * b, 0) + hazeSoftening).squareRoot()
    return (atan((max(length, 0) + b) / h) - atan(b / h)) / h
}

public let dustCount = 400

/// The air the dust drifts in: in front of the screen, between the floor and above its top.
public func dustBox(_ l: CinemaLayout) -> CinemaBox {
    let near = l.viewer.z - 1.5, far = l.screenCenter.z + 0.5
    let bottom = l.floorY + 0.2, top = l.screenTop + 0.5, w = l.screenWidth + 2
    return CinemaBox(center: Vec3(x: 0, y: (bottom + top) / 2, z: (near + far) / 2),
                     size: Vec3(x: w, y: top - bottom, z: near - far))
}

/// A repeatable pseudo-random number in [0, 1) for mote `i`, channel `k`.
func dustHash(_ i: Int, _ k: Int) -> Double {
    let s = sin(Double(i) * 12.9898 + Double(k) * 78.233) * 43758.5453
    return s - floor(s)
}

/// Where mote `i` is at `time`: slow wandering drift that wraps around inside `box`.
public func dustMote(_ i: Int, time: Double, in box: CinemaBox) -> Vec3 {
    let h = (0..<6).map { dustHash(i, $0) }
    let drift = Vec3(x: 0.25 * sin(time * 0.07 * (0.5 + h[3]) + 6.283 * h[4]),
                     y: time * 0.012 * (0.4 + h[5]),
                     z: 0.25 * sin(time * 0.05 * (0.5 + h[4]) + 6.283 * h[3]))
    func wrap(_ base: Double, _ d: Double, _ size: Double) -> Double {
        let f = base + d / size
        return f - floor(f)
    }
    return Vec3(x: box.center.x + box.size.x * (wrap(h[0], drift.x, box.size.x) - 0.5),
                y: box.center.y + box.size.y * (wrap(h[1], drift.y, box.size.y) - 0.5),
                z: box.center.z + box.size.z * (wrap(h[2], drift.z, box.size.z) - 0.5))
}
