import Foundation

public enum VirtualScreenLimits {
    public static let maxCount: UInt32 = 4
}

/// The lowest virtual screen serial no panel uses yet, or nil when all are taken.
public func nextVirtualSerial(in panels: [Panel]) -> UInt32? {
    nextFreeSerials(1, used: panels.map(\.source)).first
}

private func nextFreeSerials(_ n: Int, used: [PanelSource]) -> [UInt32] {
    let taken = Set(used.compactMap { if case .virtualScreen(let s) = $0 { s } else { nil } })
    return Array((1...VirtualScreenLimits.maxCount).filter { !taken.contains($0) }.prefix(n))
}

/// Sources to lay a preset out with: real displays first, then windows, then virtual screens.
/// Dual and Triple add virtual screens for empty slots, and Triple puts the first source in the middle.
public func presetSources(_ preset: Preset, current: [PanelSource]) -> [PanelSource] {
    func rank(_ s: PanelSource) -> Int {
        switch s {
        case .display: 0
        case .window: 1
        case .virtualScreen: 2
        case .placeholder: 3
        }
    }
    var sources = current.filter { $0.key != nil }.enumerated()
        .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    let slots: Int
    switch preset {
    case .dual: slots = 2
    case .triple: slots = 3
    default: return sources
    }
    if sources.count < slots {
        sources += nextFreeSerials(slots - sources.count, used: sources).map { .virtualScreen(serial: $0) }
    }
    if preset == .triple, sources.count >= 2 { sources.swapAt(0, 1) }
    return sources
}
