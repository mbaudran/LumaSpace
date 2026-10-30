import AppKit
import LumaCore

/// A menu item that hosts a labelled slider.
@MainActor
private final class SliderItem: NSMenuItem {
    private let onChange: (Double) -> Void

    init(title: String, value: Double, range: ClosedRange<Double>, step: Double?, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(title: title, action: nil, keyEquivalent: "")
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 20, y: 6, width: 80, height: 18)
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: nil, action: nil)
        slider.frame = NSRect(x: 100, y: 4, width: 150, height: 22)
        if let step { slider.numberOfTickMarks = Int((range.upperBound - range.lowerBound) / step) + 1; slider.allowsTickMarkValuesOnly = true }
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed(_:))
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 30))
        v.addSubview(label)
        v.addSubview(slider)
        view = v
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func changed(_ s: NSSlider) { onChange(s.doubleValue) }
}

/// The eyeglasses icon in the menu bar. The menu is rebuilt each time it opens so it shows live state.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppController

    init(app: AppController) {
        self.app = app
        super.init()
        item.button?.image = NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: "LumaSpace")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: app.glasses.status.text, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if !app.sdkLoaded { menu.addItem(action("Set Up VITURE SDK…", #selector(setUpSDK))) }
        menu.addItem(action("Show Preview", #selector(showPreview)))
        menu.addItem(.separator())

        let layout = NSMenu()
        for p in Preset.allCases { layout.addItem(command(.applyPreset(p), title: p.title)) }
        menu.addItem(submenu("Layout", layout))
        menu.addItem(command(.addSource))
        menu.addItem(command(.newVirtualScreen))
        menu.addItem(command(.arrangeDisplays))
        menu.addItem(command(.recenter))
        menu.addItem(command(.toggleGameMode, checked: app.gameMode))
        menu.addItem(command(.toggleCinemaMode, checked: app.mode == .cinema))
        let cinema = NSMenu()
        cinema.addItem(command(.cycleEnvironment, title: "Environment: \(app.cinema.environment.title)"))
        cinema.addItem(command(.cycleAmbience, title: "Ambience: \(app.cinema.ambience.title)"))
        cinema.addItem(command(.nudgeIPD(0.001), title: "Eye Distance + (\(Int((app.cinema.ipd * 1000).rounded())) mm)"))
        cinema.addItem(command(.nudgeIPD(-0.001), title: "Eye Distance −"))
        menu.addItem(submenu("Cinema", cinema))
        menu.addItem(.separator())

        let g = app.glasses
        for (kind, title) in [(LevelKind.brightness, "Brightness"), (.volume, "Volume")] {
            if let max = g.maxLevel(kind) {
                menu.addItem(SliderItem(title: title, value: Double(g.level(kind) ?? 0), range: 0...Double(max), step: 1) { [weak self] v in
                    self?.app.glasses.setLevel(kind, Int(v.rounded()))
                })
            }
        }
        menu.addItem(SliderItem(title: "Distance", value: app.distance, range: SceneLimits.distance, step: nil) { [weak self] v in
            self?.app.setDistance(v)
        })
        let rate = NSMenu()
        for r in DisplayRate.allCases {
            let i = command(.setRate(r), title: "\(r.rawValue) Hz")
            if case .simulated = g.status { i.action = nil }
            rate.addItem(i)
        }
        menu.addItem(submenu("Refresh Rate", rate))
        menu.addItem(.separator())

        menu.addItem(command(.toggleSmoothFollow, checked: app.tracker.smoothFollow))
        let lock = NSMenu()
        for a in Axis.allCases {
            lock.addItem(command(.toggleAxisLock(a), title: a.rawValue.capitalized, checked: app.tracker.lockedAxes.contains(a)))
        }
        menu.addItem(submenu("Lock Axis", lock))
        menu.addItem(command(.toggleSnap, checked: app.scene.snap.enabled))
        menu.addItem(.separator())
        menu.addItem(action("Command Palette…   ⌃⌥Space", #selector(showPalette)))
        for label in app.hotkeys?.failed ?? [] {
            let i = NSMenuItem(title: "Shortcut \(label) unavailable", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(command(.quit))
    }

    private func command(_ c: Command, title: String? = nil, checked: Bool = false) -> NSMenuItem {
        let label = Hotkeys.label(for: c).map { "   \($0)" } ?? ""
        let i = NSMenuItem(title: (title ?? c.title) + label, action: #selector(runCommand(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = CommandBox(c)
        i.state = checked ? .on : .off
        return i
    }

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    private func submenu(_ title: String, _ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        return i
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        app.perform(box.command)
    }

    @objc private func showPreview() { app.showPreview() }
    @objc private func setUpSDK() { app.setUpSDK() }
    @objc private func showPalette() { app.showPalette() }
}

private final class CommandBox: NSObject {
    let command: Command
    init(_ c: Command) { command = c }
}
