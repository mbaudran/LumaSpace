import Foundation
import LumaCore

func headTrackerChecks() {
    check("recenter makes the same pose identity") {
        let t = HeadTracker()
        let raw = Quat(yaw: 0.8, pitch: 0, roll: 0)
        t.recenter(to: raw)
        let r = t.update(raw: raw, dt: 0.016).yawPitchRoll
        expectNear(r.yaw, 0); expectNear(r.pitch, 0); expectNear(r.roll, 0)
    }
    check("recenter keeps the world level (yaw only)") {
        let t = HeadTracker()
        let raw = Quat(yaw: 0.5, pitch: 0.3, roll: 0)
        t.recenter(to: raw)
        let r = t.update(raw: raw, dt: 0.016).yawPitchRoll
        expectNear(r.yaw, 0); expectNear(r.pitch, 0.3)
    }
    check("locked yaw is zeroed") {
        let t = HeadTracker()
        t.recenter(to: .identity)
        t.lockedAxes = [.yaw]
        let r = t.update(raw: Quat(yaw: 0.6, pitch: 0.2, roll: 0), dt: 0.016).yawPitchRoll
        expectNear(r.yaw, 0); expectNear(r.pitch, 0.2)
    }
    check("smooth follow trails then settles in front") {
        let t = HeadTracker()
        t.recenter(to: .identity)
        t.smoothFollow = true
        let raw = Quat(yaw: 0.5, pitch: 0, roll: 0)
        let first = t.update(raw: raw, dt: 0.016).yawPitchRoll.yaw
        expect(first > 0.45, "first step \(first)")
        var last = first
        for _ in 0..<312 { last = t.update(raw: raw, dt: 0.016).yawPitchRoll.yaw }
        expect(abs(last) < 0.01, "after 5 s \(last)")
    }
    check("first update without recenter recenters") {
        let t = HeadTracker()
        let r = t.update(raw: Quat(yaw: 1.2, pitch: 0, roll: 0), dt: 0.016).yawPitchRoll
        expectNear(r.yaw, 0)
    }
}
