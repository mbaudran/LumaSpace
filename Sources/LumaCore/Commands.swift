import Foundation

/// Every action the menu bar, palette and shortcuts can trigger.
public enum Command: Hashable, Sendable {
    case recenter
    case applyPreset(Preset)
    case nudgeDistance(Double)
    case resizeSelected(Double)
    case adjustLevel(LevelKind, Int)
    case setRate(DisplayRate)
    case toggleSmoothFollow
    case toggleAxisLock(Axis)
    case toggleSnap
    case addSource
    case removeSelected
    case groupAll
    case ungroupSelected
    case quit

    public var title: String {
        switch self {
        case .recenter: "Recenter"
        case .applyPreset(let p): "Layout: \(p.title)"
        case .nudgeDistance(let d): d < 0 ? "Closer" : "Farther"
        case .resizeSelected(let f): f > 1 ? "Bigger" : "Smaller"
        case .adjustLevel(let k, let d): "\(k == .brightness ? "Brightness" : "Volume") \(d > 0 ? "+" : "−")"
        case .setRate(let r): "Refresh \(r.rawValue) Hz"
        case .toggleSmoothFollow: "Smooth Follow"
        case .toggleAxisLock(let a): "Lock \(a.rawValue.capitalized)"
        case .toggleSnap: "Snapping"
        case .addSource: "Add Window or Display…"
        case .removeSelected: "Remove Selected Screen"
        case .groupAll: "Group All Screens"
        case .ungroupSelected: "Ungroup Selected"
        case .quit: "Quit LumaSpace"
        }
    }

    public var keywords: [String] {
        switch self {
        case .recenter: ["center", "reset", "origin"]
        case .applyPreset(let p): ["layout", "preset", p.rawValue]
        case .nudgeDistance: ["distance", "zoom"]
        case .resizeSelected: ["size", "scale", "resize"]
        case .adjustLevel(let k, _): k == .brightness ? ["light", "dim"] : ["sound", "audio"]
        case .setRate: ["hz", "rate", "fps"]
        case .toggleSmoothFollow: ["follow", "drift"]
        case .toggleAxisLock: ["axis"]
        case .toggleSnap: ["grid", "magnet"]
        case .addSource: ["window", "display", "screen", "new"]
        case .removeSelected: ["delete", "close"]
        case .groupAll, .ungroupSelected: ["group"]
        case .quit: ["exit"]
        }
    }

    public static var all: [Command] {
        [.recenter]
            + Preset.allCases.map { .applyPreset($0) }
            + [.nudgeDistance(-0.25), .nudgeDistance(0.25), .resizeSelected(1.1), .resizeSelected(1 / 1.1),
               .adjustLevel(.brightness, 1), .adjustLevel(.brightness, -1),
               .adjustLevel(.volume, 1), .adjustLevel(.volume, -1)]
            + DisplayRate.allCases.map { .setRate($0) }
            + [.toggleSmoothFollow]
            + Axis.allCases.map { .toggleAxisLock($0) }
            + [.toggleSnap, .addSource, .removeSelected, .groupAll, .ungroupSelected, .quit]
    }
}

private func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

private func isSubsequence(_ q: String, of s: String) -> Bool {
    var it = s.makeIterator()
    for c in q {
        var found = false
        while let x = it.next() { if x == c { found = true; break } }
        if !found { return false }
    }
    return true
}

/// Ranks: title prefix, then word prefix, then subsequence; ties keep the input order.
public func paletteMatches(_ query: String, in commands: [Command]) -> [Command] {
    let q = fold(query.trimmingCharacters(in: .whitespaces))
    guard !q.isEmpty else { return commands }
    let scored: [(rank: Int, index: Int, cmd: Command)] = commands.enumerated().compactMap { i, c in
        let title = fold(c.title)
        let haystack = ([title] + c.keywords.map(fold)).joined(separator: " ")
        let words = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if title.hasPrefix(q) { return (0, i, c) }
        if words.contains(where: { $0.hasPrefix(q) }) { return (1, i, c) }
        if isSubsequence(q, of: haystack) { return (2, i, c) }
        return nil
    }
    return scored.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.cmd)
}
