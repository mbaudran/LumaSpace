import Foundation

public struct SnapSettings: Sendable {
    public var enabled = true
    public var grid = 5.0           // degrees
    public var edgeThreshold = 2.0  // degrees
    public init() {}
}

/// Snaps one axis: abut or align an edge with another panel within the threshold, else round to the grid.
private func snapAxis(target: Double, half: Double, others: [(center: Double, half: Double)],
                      settings: SnapSettings, wraps: Bool) -> Double {
    let diff: (Double, Double) -> Double = { a, b in wraps ? wrapYaw(a - b) : a - b }
    var best: Double?
    for o in others {
        let pairs: [(mine: Double, theirs: Double)] = [
            (target - half, o.center + o.half),  // abut
            (target + half, o.center - o.half),  // abut
            (target - half, o.center - o.half),  // align
            (target + half, o.center + o.half),  // align
            (target, o.center),                  // centre
        ]
        for p in pairs {
            let d = diff(p.theirs, p.mine)
            if abs(d) <= settings.edgeThreshold, best == nil || abs(d) < abs(best!) { best = d }
        }
    }
    if let d = best { return target + d }
    return (target / settings.grid).rounded() * settings.grid
}

public func snapped(_ p: Panel, toYaw yaw: Double, pitch: Double, others: [Panel],
                    settings: SnapSettings) -> (yaw: Double, pitch: Double) {
    guard settings.enabled else { return (yaw, pitch) }
    let y = snapAxis(target: yaw, half: p.angularWidth / 2,
                     others: others.map { ($0.yaw, $0.angularWidth / 2) }, settings: settings, wraps: true)
    let q = snapAxis(target: pitch, half: p.angularHeight / 2,
                     others: others.map { ($0.pitch, $0.angularHeight / 2) }, settings: settings, wraps: false)
    return (y, q)
}
