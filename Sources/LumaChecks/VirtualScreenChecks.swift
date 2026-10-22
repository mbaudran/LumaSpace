import Foundation
import LumaCore

func virtualScreenChecks() {
    let mac = PanelSource.display(id: 1, name: "Built-in Retina Display")
    let win = PanelSource.window(id: 7, app: "Safari", title: "Netflix")
    func panel(_ s: PanelSource) -> Panel { Panel(source: s, yaw: 0, pitch: 0, distance: 2, width: 1.6, aspect: 16.0 / 9) }

    check("virtual screen source: label, key, survives a save") {
        let s = PanelSource.virtualScreen(serial: 2)
        expectEqual(s.label, "Virtual Screen 2")
        expectEqual(s.key, .virtualScreen(2))
        let data = try JSONEncoder().encode(s)
        expectEqual(try JSONDecoder().decode(PanelSource.self, from: data), s)
    }
    check("next virtual serial is the lowest unused, up to 4") {
        expectEqual(nextVirtualSerial(in: [panel(mac)]), 1)
        expectEqual(nextVirtualSerial(in: [panel(.virtualScreen(serial: 1)), panel(.virtualScreen(serial: 3))]), 2)
        expectEqual(nextVirtualSerial(in: (1...4).map { panel(.virtualScreen(serial: UInt32($0))) }), nil)
    }
    check("triple puts the Mac screen between two new virtual screens") {
        expectEqual(presetSources(.triple, current: [mac]),
                    [.virtualScreen(serial: 1), mac, .virtualScreen(serial: 2)])
    }
    check("dual adds one virtual screen after the Mac screen") {
        expectEqual(presetSources(.dual, current: [mac]), [mac, .virtualScreen(serial: 1)])
    }
    check("presets keep real sources and don't add screens they don't need") {
        expectEqual(presetSources(.dual, current: [mac, win]), [mac, win])
        expectEqual(presetSources(.stacked, current: [mac]), [mac])
    }
    check("single after triple shows the Mac screen, not a virtual one") {
        let afterTriple = presetSources(.triple, current: [mac])
        expectEqual(presetSources(.single, current: afterTriple).first, mac)
    }
    check("reapplying triple reuses existing virtual screens") {
        let afterTriple = presetSources(.triple, current: [mac])
        expectEqual(Set(presetSources(.triple, current: afterTriple)), Set(afterTriple))
    }

    // Arrangement: Mac 1710×1107 (main, id 1); virtual screens 1920×1080. yaw > 0 is left.
    func placed(_ id: UInt32, yaw: Double, pitch: Double = 0, w: Double = 1920, h: Double = 1080) -> PlacedDisplay {
        PlacedDisplay(id: id, width: w, height: h, yaw: yaw, pitch: pitch)
    }
    let macPlaced = placed(1, yaw: 0, w: 1710, h: 1107)

    check("a panel to the right becomes a display to the right") {
        let o = arrangeDisplays(placed: [macPlaced, placed(4, yaw: -30)], others: [], main: 1)
        expectEqual(o[1], DisplayOrigin(x: 0, y: 0))
        expectEqual(o[4], DisplayOrigin(x: 1710, y: 13))
    }
    check("triple: left and right of the Mac screen") {
        let o = arrangeDisplays(placed: [placed(4, yaw: 30), macPlaced, placed(5, yaw: -30)], others: [], main: 1)
        expectEqual(o[4], DisplayOrigin(x: -1920, y: 13))
        expectEqual(o[5], DisplayOrigin(x: 1710, y: 13))
    }
    check("two panels on the right chain outward, nearest first") {
        let o = arrangeDisplays(placed: [macPlaced, placed(5, yaw: -60), placed(4, yaw: -30)], others: [], main: 1)
        expectEqual(o[4], DisplayOrigin(x: 1710, y: 13))
        expectEqual(o[5], DisplayOrigin(x: 3630, y: 13))
    }
    check("a panel above becomes a display above") {
        let o = arrangeDisplays(placed: [macPlaced, placed(4, yaw: 0, pitch: 30)], others: [], main: 1)
        expectEqual(o[4], DisplayOrigin(x: -105, y: -1080))
    }
    check("displays not on any panel go in a row underneath") {
        let o = arrangeDisplays(placed: [macPlaced, placed(4, yaw: -30)],
                                others: [DisplaySize(id: 9, width: 1920, height: 1080)], main: 1)
        expectEqual(o[9], DisplayOrigin(x: 0, y: 1107))
    }
    check("the main display stays at the origin even when it isn't on a panel") {
        let o = arrangeDisplays(placed: [placed(4, yaw: 10), placed(5, yaw: -10)],
                                others: [DisplaySize(id: 1, width: 1710, height: 1107)], main: 1)
        expectEqual(o[1], DisplayOrigin(x: 0, y: 0))
        expectEqual(o[4], DisplayOrigin(x: 0, y: -1080))
        expectEqual(o[5], DisplayOrigin(x: 1920, y: -1080))
    }
    check("a display on two panels is placed once, by its first panel") {
        let o = arrangeDisplays(placed: [macPlaced, placed(4, yaw: -30), placed(4, yaw: 30)], others: [], main: 1)
        expectEqual(o[4], DisplayOrigin(x: 1710, y: 13))
        expectEqual(o.count, 2)
    }
    check("new virtual screen command is findable") {
        expect(Command.all.contains(.newVirtualScreen))
        expectEqual(paletteMatches("virt", in: Command.all).first, .newVirtualScreen)
    }
}
