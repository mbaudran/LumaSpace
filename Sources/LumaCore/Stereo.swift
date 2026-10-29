import Foundation

/// Side-by-side stereo: the left eye gets the left half of the frame, the right eye the right half.
public enum Eye: CaseIterable, Sendable { case left, right }

/// Interpupillary distance in metres.
public enum IPD {
    public static let range = 0.055...0.075
    public static let standard = 0.063
}

/// Where an eye sits relative to the centre of the head, in the render frame.
public func eyeOffset(_ eye: Eye, head: Quat, ipd: Double) -> Vec3 {
    head.rotate(Vec3(x: eye == .left ? -ipd / 2 : ipd / 2, y: 0, z: 0))
}

public struct EyeViewport: Equatable, Sendable {
    public var x: Int
    public var width: Int
    public var height: Int
    public init(x: Int, width: Int, height: Int) { self.x = x; self.width = width; self.height = height }
}

/// The half of the drawable an eye renders into; the right half takes the odd pixel.
public func eyeViewport(_ eye: Eye, drawableWidth w: Int, drawableHeight h: Int) -> EyeViewport {
    eye == .left ? EyeViewport(x: 0, width: w / 2, height: h) : EyeViewport(x: w / 2, width: w - w / 2, height: h)
}

/// Aspect of one eye's half of the drawable (16:10 while the size is unknown).
public func eyeAspect(drawableWidth w: Int, drawableHeight h: Int) -> Double {
    h > 0 ? Double(w / 2) / Double(h) : 16.0 / 10
}
