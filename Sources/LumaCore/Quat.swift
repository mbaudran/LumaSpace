import Foundation

/// Right-handed render frame: X right, Y up, −Z forward.
public struct Vec3: Equatable, Codable, Sendable {
    public var x, y, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }

    public static let zero = Vec3(x: 0, y: 0, z: 0)
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }
    public func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Vec3) -> Vec3 { Vec3(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x) }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
}

public struct Quat: Equatable, Codable, Sendable {
    public var w, x, y, z: Double
    public init(w: Double, x: Double, y: Double, z: Double) { self.w = w; self.x = x; self.y = y; self.z = z }

    public static let identity = Quat(w: 1, x: 0, y: 0, z: 0)

    /// Rotation of `angle` radians about `axis`.
    public init(axis: Vec3, angle: Double) {
        let a = axis.normalized, s = sin(angle / 2)
        self.init(w: cos(angle / 2), x: a.x * s, y: a.y * s, z: a.z * s)
    }

    /// Yaw about +Y, then pitch about +X, then roll about +Z (radians).
    public init(yaw: Double, pitch: Double, roll: Double) {
        self = Quat(axis: Vec3(x: 0, y: 1, z: 0), angle: yaw)
            * Quat(axis: Vec3(x: 1, y: 0, z: 0), angle: pitch)
            * Quat(axis: Vec3(x: 0, y: 0, z: 1), angle: roll)
    }

    public static func * (a: Quat, b: Quat) -> Quat {
        Quat(w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
             x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
    }

    public var conjugate: Quat { Quat(w: w, x: -x, y: -y, z: -z) }

    public var normalized: Quat {
        let l = (w * w + x * x + y * y + z * z).squareRoot()
        return l > 0 ? Quat(w: w / l, x: x / l, y: y / l, z: z / l) : .identity
    }

    public func rotate(_ v: Vec3) -> Vec3 {
        let r = self * Quat(w: 0, x: v.x, y: v.y, z: v.z) * conjugate
        return Vec3(x: r.x, y: r.y, z: r.z)
    }

    public static func slerp(_ a: Quat, _ b: Quat, _ t: Double) -> Quat {
        var b = b
        var d = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
        if d < 0 { b = Quat(w: -b.w, x: -b.x, y: -b.y, z: -b.z); d = -d }
        if d > 0.9995 {
            return Quat(w: a.w + (b.w - a.w) * t, x: a.x + (b.x - a.x) * t,
                        y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t).normalized
        }
        let theta = acos(d), s = sin(theta)
        let ka = sin((1 - t) * theta) / s, kb = sin(t * theta) / s
        return Quat(w: a.w * ka + b.w * kb, x: a.x * ka + b.x * kb,
                    y: a.y * ka + b.y * kb, z: a.z * ka + b.z * kb)
    }

    /// Inverse of `init(yaw:pitch:roll:)` (radians).
    public var yawPitchRoll: (yaw: Double, pitch: Double, roll: Double) {
        // q = Ry(yaw) · Rx(pitch) · Rz(roll); read angles from the rotation matrix.
        let m12 = 2 * (y * z - w * x)            // R[1][2] = -sin(pitch)
        let pitch = asin(max(-1, min(1, -m12)))
        let yaw = atan2(2 * (x * z + w * y), 1 - 2 * (x * x + y * y))   // R[0][2], R[2][2]
        let roll = atan2(2 * (x * y + w * z), 1 - 2 * (x * x + z * z))  // R[1][0], R[1][1]
        return (yaw, pitch, roll)
    }
}

/// Converts an SDK pose quaternion in North-West-Up into the render frame.
/// The vector map r = (−y_n, z_n, −x_n) is a proper rotation, so it applies to the vector part.
public func renderQuat(fromNWU w: Double, _ x: Double, _ y: Double, _ z: Double) -> Quat {
    Quat(w: w, x: -y, y: z, z: -x)
}
