import Foundation
import LumaCore

private func win(_ id: UInt32, _ app: String, _ title: String, pid: Int32 = 100, layer: Int = 0, onScreen: Bool = true) -> WindowInfo {
    WindowInfo(id: id, app: app, title: title, ownerPID: pid, layer: layer, onScreen: onScreen)
}

func captureSourceChecks() {
    check("glasses display is never offered") {
        let s = offeredSources(displays: [DisplayInfo(id: 1, name: "Built-in"), DisplayInfo(id: 7, name: "VITURE")],
                               windows: [], glassesDisplayID: 7, ownPID: 1)
        expectEqual(s, [.display(id: 1, name: "Built-in")])
    }
    check("own, non-normal, untitled and off-screen windows are excluded") {
        let s = offeredSources(displays: [], windows: [
            win(1, "LumaSpace", "Simulator", pid: 42),
            win(2, "Dock", "Dock", layer: 25),
            win(3, "Finder", ""),
            win(4, "Notes", "Hidden", onScreen: false),
            win(5, "Safari", "Docs"),
        ], glassesDisplayID: nil, ownPID: 42)
        expectEqual(s, [.window(id: 5, app: "Safari", title: "Docs")])
    }
    check("displays first, then windows by app and title") {
        let s = offeredSources(displays: [DisplayInfo(id: 1, name: "Built-in")], windows: [
            win(9, "Safari", "b"), win(8, "Code", "z"), win(7, "Safari", "a"),
        ], glassesDisplayID: nil, ownPID: 1)
        expectEqual(s, [.display(id: 1, name: "Built-in"), .window(id: 8, app: "Code", title: "z"),
                        .window(id: 7, app: "Safari", title: "a"), .window(id: 9, app: "Safari", title: "b")])
    }
}
