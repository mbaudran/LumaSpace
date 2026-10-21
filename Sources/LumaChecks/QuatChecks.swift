import Foundation
import LumaCore

private func expectVec(_ a: Vec3, _ b: Vec3, tol: Double = 1e-6, file: StaticString = #fileID, line: UInt = #line) {
    expectNear(a.x, b.x, tol: tol, "x", file: file, line: line)
    expectNear(a.y, b.y, tol: tol, "y", file: file, line: line)
    expectNear(a.z, b.z, tol: tol, "z", file: file, line: line)
}

func quatChecks() {
    check("rotate: turning left 90° points forward to the left") {
        let q = Quat(axis: Vec3(x: 0, y: 1, z: 0), angle: .pi / 2)
        expectVec(q.rotate(Vec3(x: 0, y: 0, z: -1)), Vec3(x: -1, y: 0, z: 0))
    }
    check("q * conjugate is identity") {
        let q = Quat(yaw: 0.3, pitch: -0.2, roll: 0.1)
        let r = q * q.conjugate
        expectNear(r.w, 1); expectNear(r.x, 0); expectNear(r.y, 0); expectNear(r.z, 0)
    }
    check("yawPitchRoll round-trips") {
        let a = Quat(yaw: 0.4, pitch: -0.3, roll: 0.2).yawPitchRoll
        expectNear(a.yaw, 0.4, tol: 1e-9)
        expectNear(a.pitch, -0.3, tol: 1e-9)
        expectNear(a.roll, 0.2, tol: 1e-9)
    }
    check("slerp halfway halves the yaw") {
        let s = Quat.slerp(.identity, Quat(axis: Vec3(x: 0, y: 1, z: 0), angle: 1.0), 0.5)
        expectNear(s.yawPitchRoll.yaw, 0.5)
    }
    check("NWU yaw-left 90° maps to render left turn") {
        let c = cos(Double.pi / 4), s = sin(Double.pi / 4)
        let q = renderQuat(fromNWU: c, 0, 0, s)
        expectVec(q.rotate(Vec3(x: 0, y: 0, z: -1)), Vec3(x: -1, y: 0, z: 0))
    }
    check("NWU nose-up 30° maps to render pitch up") {
        let n = Quat(axis: Vec3(x: 0, y: 1, z: 0), angle: -.pi / 6)
        let q = renderQuat(fromNWU: n.w, n.x, n.y, n.z)
        expectNear(q.rotate(Vec3(x: 0, y: 0, z: -1)).y, 0.5)
    }
}
