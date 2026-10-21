import Foundation
import LumaCore

private func tempStore() -> LayoutStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("luma-\(UUID().uuidString)")
    return LayoutStore(url: dir.appendingPathComponent("layout.json"))
}

func layoutChecks() {
    check("triple preset: placeholders, centred, abutting, one group") {
        let ps = Preset.triple.panels(sources: [], distance: 2)
        expectEqual(ps.count, 3)
        expect(ps.allSatisfy { if case .placeholder = $0.source { true } else { false } })
        expectNear(ps[1].yaw, 0)
        expectNear(ps[0].yaw - ps[0].angularWidth / 2, ps[1].yaw + ps[1].angularWidth / 2, tol: 1e-6)
        expectEqual(Set(ps.map(\.groupID)).count, 1)
        expect(ps[0].groupID != nil)
    }
    check("coding preset: portrait · landscape · portrait") {
        let ps = Preset.coding.panels(sources: [], distance: 2)
        expectNear(ps[1].aspect, 16.0 / 9); expectNear(ps[0].aspect, 9.0 / 16); expectNear(ps[2].aspect, 9.0 / 16)
    }
    check("save then load round-trips") {
        let store = tempStore()
        var f = LayoutFile.default
        f.distance = 3.5; f.smoothFollow = true; f.lockedAxes = [.roll]
        try store.save(f)
        expectEqual(store.load(), f)
    }
    check("missing file loads the default") {
        let f = tempStore().load()
        expectEqual(f.panels.count, 1); expectNear(f.distance, 2)
    }
    check("corrupt file loads default and is kept as .bad") {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url)
        expectEqual(store.load().panels.count, 1)
        expect(FileManager.default.fileExists(atPath: store.url.path + ".bad"))
    }
    check("unknown version loads default and is kept as .bad") {
        let store = tempStore()
        var f = LayoutFile.default
        f.version = 99
        try store.save(f)
        expectEqual(store.load().version, 1)
        expect(FileManager.default.fileExists(atPath: store.url.path + ".bad"))
    }
}
