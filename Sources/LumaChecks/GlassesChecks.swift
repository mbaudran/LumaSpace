import Foundation
import LumaCore

@MainActor
func glassesChecks() {
    check("no SDK library → simulator") {
        expectEqual(chooseGlasses(libraryLoaded: false, devicePIDs: [0x1101]), .simulated(reason: "VITURE SDK not found"))
    }
    check("no device → simulator") {
        expectEqual(chooseGlasses(libraryLoaded: true, devicePIDs: []), .simulated(reason: "Glasses not connected"))
    }
    check("device present → real, first PID") {
        expectEqual(chooseGlasses(libraryLoaded: true, devicePIDs: [0x1101, 0x1101]), .real(pid: 0x1101))
    }
    check("simulator clamps levels") {
        let g = SimulatedGlasses(reason: "test")
        g.setLevel(.brightness, 20)
        expectEqual(g.level(.brightness), 8)
        g.setLevel(.brightness, -3)
        expectEqual(g.level(.brightness), 0)
        expectEqual(g.maxLevel(.volume), 8)
    }
    check("simulator orientation follows yaw") {
        let g = SimulatedGlasses(reason: "test")
        g.yaw = 0.5
        expectNear(g.rawOrientation().yawPitchRoll.yaw, 0.5)
        expectEqual(g.status, .simulated(reason: "test"))
    }
}
