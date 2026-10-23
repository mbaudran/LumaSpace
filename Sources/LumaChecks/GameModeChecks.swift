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
