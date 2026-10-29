import Foundation
import LumaCore

func stereoChecks() {
    check("eyes sit ipd apart on head-local x, symmetric") {
        let l = eyeOffset(.left, head: .identity, ipd: 0.063), r = eyeOffset(.right, head: .identity, ipd: 0.063)
        expectNear(l.x, -0.0315); expectNear(r.x, 0.0315); expectNear(l.y, 0); expectNear(r.z, 0)
    }
    check("eye offsets turn with the head") {
        let h = Quat(yaw: .pi / 2, pitch: 0, roll: 0)
        let r = eyeOffset(.right, head: h, ipd: 0.06)
        expectNear((r - eyeOffset(.left, head: h, ipd: 0.06)).length, 0.06)
        expectNear(abs(r.z), 0.03, tol: 1e-9); expectNear(r.x, 0, tol: 1e-9)
    }
    check("viewports split the drawable exactly, odd widths too") {
        for w in [3840, 1920, 1281] {
            let l = eyeViewport(.left, drawableWidth: w, drawableHeight: 1200)
            let r = eyeViewport(.right, drawableWidth: w, drawableHeight: 1200)
            expectEqual(l.x, 0); expectEqual(r.x, l.width); expectEqual(l.width + r.width, w); expectEqual(r.height, 1200)
        }
    }
    check("each eye's aspect uses half the width") {
        expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 1200), 1.6)
        expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 0), 1.6)
    }
}
