import Foundation

public enum Preset: String, CaseIterable, Codable, Sendable {
    case single, dual, triple, stacked, ultrawide, coding

    public var title: String {
        switch self {
        case .single: "Single"
        case .dual: "Dual"
        case .triple: "Triple"
        case .stacked: "Stacked"
        case .ultrawide: "Ultrawide"
        case .coding: "Coding"
        }
    }

    /// Panels for this preset; sources fill in order and missing ones become placeholders.
    /// Sizes are given for 2 m and scaled so the angular size is the same at any distance.
    public func panels(sources: [PanelSource], distance: Double) -> [Panel] {
        let landscape = (width: 1.6, aspect: 16.0 / 9), portrait = (width: 0.9, aspect: 9.0 / 16)
        let shapes: [(width: Double, aspect: Double)]
        switch self {
        case .single: shapes = [landscape]
        case .dual: shapes = [landscape, landscape]
        case .triple, .stacked: shapes = [landscape, landscape, landscape]
        case .ultrawide: shapes = [(3.2, 32.0 / 9)]
        case .coding: shapes = [portrait, landscape, portrait]
        }
        let group = UUID()
        let scale = distance / 2
        var panels = shapes.enumerated().map { i, s in
            Panel(source: i < sources.count ? sources[i] : .placeholder("Screen \(i + 1)"),
                  yaw: 0, pitch: 0, distance: distance, width: s.width * scale, aspect: s.aspect, groupID: group)
        }
        if self == .stacked {
            let h = panels[0].angularHeight
            panels[0].pitch = h / 2
            panels[1].pitch = -h / 2; panels[2].pitch = -h / 2
            layOutRow(&panels, indices: [1, 2])
        } else {
            layOutRow(&panels, indices: Array(panels.indices))
        }
        return panels
    }
}

/// Places panels left to right, edges touching, centred on yaw 0 (yaw > 0 is left).
private func layOutRow(_ panels: inout [Panel], indices: [Int]) {
    let total = indices.reduce(0) { $0 + panels[$1].angularWidth }
    var left = total / 2
    for i in indices {
        let w = panels[i].angularWidth
        panels[i].yaw = left - w / 2
        left -= w
    }
}
