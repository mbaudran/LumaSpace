import AppKit
import Carbon.HIToolbox
import LumaCore

/// What a global shortcut does: a command, or opening the palette.
enum HotkeyAction: Equatable { case palette, command(Command) }

struct HotkeySpec {
    let keyCode: Int
    let shift: Bool
    let label: String   // e.g. "⌃⌥R"
    let action: HotkeyAction
}

/// Global ⌃⌥ shortcuts via Carbon RegisterEventHotKey (works without Accessibility permission).
@MainActor
final class Hotkeys {
    static let specs: [HotkeySpec] = {
        var s: [HotkeySpec] = [
            HotkeySpec(keyCode: kVK_Space, shift: false, label: "⌃⌥Space", action: .palette),
            HotkeySpec(keyCode: kVK_ANSI_R, shift: false, label: "⌃⌥R", action: .command(.recenter)),
            HotkeySpec(keyCode: kVK_ANSI_Equal, shift: false, label: "⌃⌥=", action: .command(.nudgeDistance(-0.25))),
            HotkeySpec(keyCode: kVK_ANSI_Minus, shift: false, label: "⌃⌥-", action: .command(.nudgeDistance(0.25))),
            HotkeySpec(keyCode: kVK_ANSI_RightBracket, shift: false, label: "⌃⌥]", action: .command(.resizeSelected(1.1))),
            HotkeySpec(keyCode: kVK_ANSI_LeftBracket, shift: false, label: "⌃⌥[", action: .command(.resizeSelected(1 / 1.1))),
            HotkeySpec(keyCode: kVK_ANSI_F, shift: false, label: "⌃⌥F", action: .command(.toggleSmoothFollow)),
            HotkeySpec(keyCode: kVK_ANSI_A, shift: false, label: "⌃⌥A", action: .command(.addSource)),
            HotkeySpec(keyCode: kVK_ANSI_N, shift: false, label: "⌃⌥N", action: .command(.newVirtualScreen)),
            HotkeySpec(keyCode: kVK_ANSI_G, shift: false, label: "⌃⌥G", action: .command(.toggleGameMode)),
            HotkeySpec(keyCode: kVK_ANSI_B, shift: false, label: "⌃⌥B", action: .command(.adjustLevel(.brightness, 1))),
            HotkeySpec(keyCode: kVK_ANSI_B, shift: true, label: "⌃⌥⇧B", action: .command(.adjustLevel(.brightness, -1))),
        ]
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]
        for (i, p) in Preset.allCases.enumerated() where i < digits.count {
            s.append(HotkeySpec(keyCode: digits[i], shift: false, label: "⌃⌥\(i + 1)", action: .command(.applyPreset(p))))
        }
        return s
    }()

    static func label(for c: Command) -> String? {
        specs.first { $0.action == .command(c) }?.label
    }

    nonisolated(unsafe) private static var handler: ((HotkeyAction) -> Void)?
    private(set) var failed: [String] = []
    private var refs: [EventHotKeyRef] = []

    init(handler: @escaping (HotkeyAction) -> Void) {
        Hotkeys.handler = handler
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let i = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if i < Hotkeys.specs.count { Hotkeys.handler?(Hotkeys.specs[i].action) }
                }
            }
            return noErr
        }, 1, &type, nil, nil)

        for (i, spec) in Hotkeys.specs.enumerated() {
            var ref: EventHotKeyRef?
            let mods = UInt32(controlKey | optionKey | (spec.shift ? shiftKey : 0))
            let status = RegisterEventHotKey(UInt32(spec.keyCode), mods, EventHotKeyID(signature: OSType(0x4C554D41), id: UInt32(i)),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else {
                failed.append(spec.label)
                NSLog("LumaSpace: shortcut \(spec.label) unavailable (\(status))")
            }
        }
    }
}
