import Foundation
import LumaCore

func gameModeChecks() {
    let current: [UInt32: DisplayOrigin] = [1: DisplayOrigin(x: 0, y: 0), 9: DisplayOrigin(x: 0, y: 1107),
                                            4: DisplayOrigin(x: 1710, y: 13)]
    check("making the glasses main moves it to the origin and keeps the layout") {
        expectEqual(originsMakingMain(9, current: current),
                    [1: DisplayOrigin(x: 0, y: -1107), 9: DisplayOrigin(x: 0, y: 0), 4: DisplayOrigin(x: 1710, y: -1094)])
    }
    check("making main again undoes it") {
        let swapped = originsMakingMain(9, current: current)!
        expectEqual(originsMakingMain(1, current: swapped), current)
    }
    check("a display that isn't there can't become main") {
        expectEqual(originsMakingMain(42, current: current), nil)
    }
    check("game mode is a command, findable as 'steam' and 'game'") {
        expect(Command.all.contains(.toggleGameMode))
        expectEqual(paletteMatches("game", in: Command.all).first, .toggleGameMode)
        expect(paletteMatches("steam", in: Command.all).contains(.toggleGameMode))
    }
}

func gameModeLauncherChecks() {
    let glasses: UInt32 = 9, mac: UInt32 = 1
    check("waits for the glasses display, then makes it main") {
        var l = GameModeLauncher(start: 0)
        expectEqual(l.next(now: 0.5, glassesID: nil, mainID: mac), .wait)
        expectEqual(l.next(now: 1.0, glassesID: glasses, mainID: mac), .makeGlassesMain)
    }
    check("opens Big Picture only once the glasses have stayed main for a second") {
        var l = GameModeLauncher(start: 0)
        expectEqual(l.next(now: 0.5, glassesID: glasses, mainID: glasses), .wait)
        expectEqual(l.next(now: 1.0, glassesID: glasses, mainID: glasses), .wait)
        expectEqual(l.next(now: 1.5, glassesID: glasses, mainID: glasses), .openBigPicture)
        expectEqual(l.next(now: 2.0, glassesID: glasses, mainID: glasses), .wait)
    }
    check("a reset back to the Mac restarts the wait") {
        var l = GameModeLauncher(start: 0)
        _ = l.next(now: 0.5, glassesID: glasses, mainID: glasses)
        expectEqual(l.next(now: 1.0, glassesID: glasses, mainID: mac), .makeGlassesMain)
        expectEqual(l.next(now: 1.5, glassesID: glasses, mainID: glasses), .wait)
        expectEqual(l.next(now: 2.5, glassesID: glasses, mainID: glasses), .openBigPicture)
    }
    check("keeps the glasses main after Big Picture opened") {
        var l = GameModeLauncher(start: 0)
        _ = l.next(now: 0.5, glassesID: glasses, mainID: glasses)
        _ = l.next(now: 1.5, glassesID: glasses, mainID: glasses)
        expectEqual(l.next(now: 3.0, glassesID: glasses, mainID: mac), .makeGlassesMain)
    }
    check("opens Big Picture anyway after 10 s, so the game still starts") {
        var l = GameModeLauncher(start: 0)
        expectEqual(l.next(now: 9.5, glassesID: glasses, mainID: mac), .makeGlassesMain)
        expectEqual(l.next(now: 10.5, glassesID: glasses, mainID: mac), .openBigPicture)
    }
}
