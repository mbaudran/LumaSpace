import Foundation

/// The layout model: every virtual screen and the edits that can be made to it. No rendering.
public final class SpatialScene {
    public private(set) var panels: [Panel] = []
    public var selectedID: UUID?
    public var snap = SnapSettings()

    public init(panels: [Panel] = []) { replaceAll(panels) }

    @discardableResult
    public func add(_ p: Panel) -> UUID {
        var p = p
        p.yaw = wrapYaw(p.yaw)
        p.pitch = clamp(p.pitch, SceneLimits.pitch)
        p.distance = clamp(p.distance, SceneLimits.distance)
        p.width = clamp(p.width, SceneLimits.width)
        panels.append(p)
        return p.id
    }

    public func remove(_ id: UUID) {
        panels.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    public func panel(_ id: UUID) -> Panel? { panels.first { $0.id == id } }

    func index(_ id: UUID) -> Int? { panels.firstIndex { $0.id == id } }

    /// Snaps the dragged panel against panels outside its group, then moves the whole group by the same delta.
    public func move(_ id: UUID, toYaw yaw: Double, pitch: Double) {
        guard let i = index(id) else { return }
        let p = panels[i]
        let members = members(of: p)
        let others = panels.filter { !members.contains($0.id) }
        let t = snapped(p, toYaw: yaw, pitch: pitch, others: others, settings: snap)
        let dYaw = wrapYaw(t.yaw - p.yaw)
        let dPitch = clamp(t.pitch, SceneLimits.pitch) - p.pitch
        for j in panels.indices where members.contains(panels[j].id) {
            panels[j].yaw = wrapYaw(panels[j].yaw + dYaw)
            panels[j].pitch = clamp(panels[j].pitch + dPitch, SceneLimits.pitch)
        }
    }

    private func members(of p: Panel) -> Set<UUID> {
        guard let g = p.groupID else { return [p.id] }
        return Set(panels.filter { $0.groupID == g }.map(\.id))
    }

    public func group(_ ids: [UUID]) {
        let g = UUID()
        for i in panels.indices where ids.contains(panels[i].id) { panels[i].groupID = g }
    }

    public func ungroup(_ id: UUID) {
        guard let i = index(id) else { return }
        panels[i].groupID = nil
    }

    public func resize(_ id: UUID, width: Double) {
        guard let i = index(id) else { return }
        panels[i].width = clamp(width, SceneLimits.width)
    }

    public func setDistance(_ d: Double) {
        let d = clamp(d, SceneLimits.distance)
        for i in panels.indices { panels[i].distance = d }
    }

    /// Nearest panel containing the direction; the later-added one wins ties.
    public func hitTest(yaw: Double, pitch: Double) -> UUID? {
        var best: Panel?
        for p in panels where p.contains(yaw: yaw, pitch: pitch) {
            if best == nil || p.distance <= best!.distance { best = p }
        }
        return best?.id
    }

    public func updateAvailability(available: Set<SourceKey>) {
        for i in panels.indices {
            guard let key = panels[i].source.key else { panels[i].available = true; continue }
            panels[i].available = available.contains(key)
        }
    }

    public func replaceAll(_ panels: [Panel]) {
        self.panels = []
        for p in panels { add(p) }
        if let s = selectedID, panel(s) == nil { selectedID = nil }
    }
}
