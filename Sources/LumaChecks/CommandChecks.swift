import Foundation
import LumaCore

func commandChecks() {
    check("empty query returns every command in order") {
        expectEqual(paletteMatches("", in: Command.all), Command.all)
    }
    check("'tri' ranks Triple first") {
        expectEqual(paletteMatches("tri", in: Command.all).first, .applyPreset(.triple))
    }
    check("'rec' ranks Recenter first") {
        expectEqual(paletteMatches("rec", in: Command.all).first, .recenter)
    }
    check("'bri+' finds brightness up") {
        expect(paletteMatches("bri+", in: Command.all).contains(.adjustLevel(.brightness, 1)))
    }
    check("nonsense matches nothing") {
        expect(paletteMatches("zzzz", in: Command.all).isEmpty)
    }
    check("keywords match: 'center' finds Recenter") {
        expect(paletteMatches("center", in: Command.all).contains(.recenter))
    }
}
