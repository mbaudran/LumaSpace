import Foundation

/// A macOS display shown on a panel, with its size in points and its panel's direction.
public struct PlacedDisplay: Equatable, Sendable {
    public var id: UInt32
    public var width: Double
    public var height: Double
    public var yaw: Double
    public var pitch: Double
    public init(id: UInt32, width: Double, height: Double, yaw: Double, pitch: Double) {
        self.id = id; self.width = width; self.height = height; self.yaw = yaw; self.pitch = pitch
    }
}

public struct DisplaySize: Equatable, Sendable {
    public var id: UInt32
    public var width: Double
    public var height: Double
    public init(id: UInt32, width: Double, height: Double) { self.id = id; self.width = width; self.height = height }
}

/// Top-left corner in macOS global display coordinates (y down, main display at 0,0).
public struct DisplayOrigin: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// Arranges displays the way their panels sit, so the mouse leaves one screen into the panel
/// next to it. Each panel goes left, right, above or below the anchor (the main display's panel,
/// else the first), chaining outward nearest first. Displays not on a panel go in a row underneath.
public func arrangeDisplays(placed: [PlacedDisplay], others: [DisplaySize], main: UInt32) -> [UInt32: DisplayOrigin] {
    var unique: [PlacedDisplay] = []
    for p in placed where !unique.contains(where: { $0.id == p.id }) { unique.append(p) }
    var rects: [UInt32: (x: Double, y: Double, w: Double, h: Double)] = [:]

    if let anchor = unique.first(where: { $0.id == main }) ?? unique.first {
        rects[anchor.id] = (0, 0, anchor.width, anchor.height)
        var right: [(Double, PlacedDisplay)] = [], left = right, up = right, down = right
        for p in unique where p.id != anchor.id {
            let dx = anchor.yaw - p.yaw, dy = p.pitch - anchor.pitch  // right / up are positive
            if abs(dx) >= abs(dy) {
                if dx > 0 { right.append((dx, p)) } else { left.append((-dx, p)) }
            } else {
                if dy > 0 { up.append((dy, p)) } else { down.append((-dy, p)) }
            }
        }
        func nearestFirst(_ a: [(Double, PlacedDisplay)]) -> [PlacedDisplay] { a.sorted { $0.0 < $1.0 }.map(\.1) }
        let midY = { (h: Double) in ((anchor.height - h) / 2).rounded(.down) }
        let midX = { (w: Double) in ((anchor.width - w) / 2).rounded(.down) }
        var edge = anchor.width
        for p in nearestFirst(right) { rects[p.id] = (edge, midY(p.height), p.width, p.height); edge += p.width }
        edge = 0
        for p in nearestFirst(left) { edge -= p.width; rects[p.id] = (edge, midY(p.height), p.width, p.height) }
        edge = 0
        for p in nearestFirst(up) { edge -= p.height; rects[p.id] = (midX(p.width), edge, p.width, p.height) }
        edge = anchor.height
        for p in nearestFirst(down) { rects[p.id] = (midX(p.width), edge, p.width, p.height); edge += p.height }
    }

    let rest = others.filter { rects[$0.id] == nil }
    if !rest.isEmpty {
        var x = rects.values.map(\.x).min() ?? 0
        let y = rects.values.map { $0.y + $0.h }.max() ?? 0
        for o in rest { rects[o.id] = (x, y, o.width, o.height); x += o.width }
    }

    let shift = rects[main].map { ($0.x, $0.y) } ?? (0, 0)
    return rects.mapValues { DisplayOrigin(x: Int($0.x - shift.0), y: Int($0.y - shift.1)) }
}

/// The same arrangement shifted so `id` sits at the origin, which makes it the main display.
/// Nil when `id` isn't one of the displays.
public func originsMakingMain(_ id: UInt32, current: [UInt32: DisplayOrigin]) -> [UInt32: DisplayOrigin]? {
    guard let o = current[id] else { return nil }
    return current.mapValues { DisplayOrigin(x: $0.x - o.x, y: $0.y - o.y) }
}
