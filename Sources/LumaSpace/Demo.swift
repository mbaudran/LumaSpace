import AppKit
import LumaCore

/// Debug aid for verification without Accessibility permission:
/// `LUMA_DEMO=triple-drag` applies Triple, drags the right screen 15° away, then back to 1° from its neighbour
/// (snapping should close the gap).
@MainActor
enum Demo {
    static func runIfRequested(_ app: AppController) {
        guard let demo = ProcessInfo.processInfo.environment["LUMA_DEMO"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch demo {
            case "triple-drag":
                app.perform(.applyPreset(.triple))
                guard let right = app.scene.panels.min(by: { $0.yaw < $1.yaw }) else { return }
                app.scene.ungroup(right.id)  // presets are grouped; drag this one on its own
                let g = Grab()
                _ = g.begin(scene: app.scene, yaw: right.yaw, pitch: right.pitch)
                g.drag(scene: app.scene, dx: 150, dy: 0)   // 15° further right
                g.drag(scene: app.scene, dx: -140, dy: 0)  // back to 1° gap
                g.end()
                app.markDirty()
            default:
                NSLog("LumaSpace: unknown LUMA_DEMO \(demo)")
            }
        }
    }
}
