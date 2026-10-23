import AppKit
import CGVirtualDisplayShim
import LumaCore

/// The extra macOS displays behind virtual screen panels. They exist only while LumaSpace runs;
/// when it quits macOS moves their windows back to the remaining screens, like unplugging a monitor.
@MainActor
final class VirtualDisplays {
    private var displays: [UInt32: CGVirtualDisplay] = [:]

    /// Display id of each live virtual screen, by serial.
    var ids: [UInt32: CGDirectDisplayID] { displays.mapValues(\.displayID) }

    /// Creates the virtual screens in `serials` and destroys the rest. Returns whether anything changed.
    @discardableResult
    func sync(serials: Set<UInt32>) -> Bool {
        var changed = false
        for serial in displays.keys where !serials.contains(serial) {
            displays[serial] = nil  // releasing a CGVirtualDisplay removes the display
            changed = true
        }
        for serial in serials.sorted() where displays[serial] == nil {
            guard let d = Self.make(serial: serial) else {
                NSLog("LumaSpace: could not create virtual screen \(serial)")
                continue
            }
            displays[serial] = d
            changed = true
        }
        return changed
    }

    /// A 1920×1080-point HiDPI display (3840×2160 pixels). The serial keeps macOS's per-display
    /// settings stable across launches.
    private static func make(serial: UInt32) -> CGVirtualDisplay? {
        let desc = CGVirtualDisplayDescriptor()
        desc.queue = DispatchQueue.main
        desc.name = "LumaSpace Screen \(serial)"
        desc.maxPixelsWide = 3840
        desc.maxPixelsHigh = 2160
        desc.sizeInMillimeters = CGSize(width: 531, height: 299)  // a 24" 16:9 monitor
        desc.serialNum = serial
        desc.vendorID = 0x4C53
        desc.productID = 0x5653
        guard let display = CGVirtualDisplay(descriptor: desc) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)]
        return display.apply(settings) ? display : nil
    }
}

/// Moves displays so they sit the way their panels do. Only touches the arrangement while
/// virtual screens exist, and only when it differs from the current one.
@MainActor
func arrangeDisplays(for panels: [Panel], virtualIDs: [UInt32: CGDirectDisplayID]) {
    guard !virtualIDs.isEmpty else { return }
    let ids = arrangeableDisplayIDs()

    var placed: [PlacedDisplay] = []
    for p in panels {
        let id: CGDirectDisplayID? = switch p.source {
        case .display(let id, _): id
        case .virtualScreen(let serial): virtualIDs[serial]
        default: nil
        }
        guard let id, ids.contains(id) else { continue }
        let b = CGDisplayBounds(id)
        placed.append(PlacedDisplay(id: id, width: b.width, height: b.height, yaw: p.yaw, pitch: p.pitch))
    }
    let others = ids.filter { id in !placed.contains { $0.id == id } }.map {
        DisplaySize(id: $0, width: CGDisplayBounds($0).width, height: CGDisplayBounds($0).height)
    }
    applyDisplayOrigins(LumaCore.arrangeDisplays(placed: placed, others: others, main: CGMainDisplayID()))
}

/// Active displays, minus mirrors (they follow their mirror source).
func arrangeableDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var active = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &active, &count)
    return active.filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
}

func currentDisplayOrigins() -> [UInt32: DisplayOrigin] {
    Dictionary(uniqueKeysWithValues: arrangeableDisplayIDs().map { id in
        let b = CGDisplayBounds(id)
        return (id, DisplayOrigin(x: Int(b.origin.x), y: Int(b.origin.y)))
    })
}

/// Moves displays for this login session; does nothing when they're already there.
func applyDisplayOrigins(_ target: [UInt32: DisplayOrigin]) {
    let current = currentDisplayOrigins()
    guard target.contains(where: { current[$0.key] != $0.value }) else { return }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
    for (id, o) in target { CGConfigureDisplayOrigin(config, id, Int32(o.x), Int32(o.y)) }
    if CGCompleteDisplayConfiguration(config, .forSession) != .success {
        NSLog("LumaSpace: could not arrange displays")
    }
}
