import AppKit
import LumaCore
import MetalKit

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    /// `LUMA_LAYOUT=/path.json` points at another layout file (used for testing).
    let store = LayoutStore(url: ProcessInfo.processInfo.environment["LUMA_LAYOUT"].map { URL(fileURLWithPath: $0) }
        ?? LayoutStore.defaultURL())
    let scene = SpatialScene()
    let tracker = HeadTracker()
    var glasses: GlassesLink = SimulatedGlasses(reason: "Glasses not connected")
    var distance = 2.0

    var window: NSWindow!
    var view: LumaView!
    var renderer: Renderer!
    var capture: CaptureService!
    var offeredSources: [PanelSource] = []
    private var permissionView: PermissionView?
    let grab = Grab()
    let picker = SourcePicker()
    let palette = PaletteWindow()
    var hotkeys: Hotkeys?
    private var menuBar: MenuBarController?
    private let sdk = VitureLibrary.load()
    private let virtualDisplays = VirtualDisplays()
    private var glassesWindow: NSWindow?
    private var missedPolls = 0
    private var grabMouse: NSPoint?
    private var grabArming = GrabArming()
    /// Glasses that couldn't be opened (e.g. SpaceWalker holds them) are retried every 15 s, not every poll.
    private let bringUp = RetryGate<Int>(delay: 15)
    private var recenterOnFirstSample = false
    /// Called after any command so menus can refresh their checkmarks and sliders.
    var onStateChange: () -> Void = {}

    private var head = Quat.identity
    private var lastFrame = CACurrentMediaTime()
    private var dirty = false
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        loadLayout()
        window = OutputWindow.preview()
        view = LumaView(frame: window.contentView!.bounds, device: MTLCreateSystemDefaultDevice())
        view.autoresizingMask = [.width, .height]
        view.preferredFramesPerSecond = 60
        window.contentView!.addSubview(view)
        guard let r = Renderer(view: view, scene: scene) else {
            fatalError("LumaSpace needs Metal")
        }
        renderer = r
        renderer.headOrientation = { [unowned self] in self.frameHead() }
        view.scene = scene
        view.head = { [unowned self] in self.head }
        view.simulator = glasses as? SimulatedGlasses
        view.onRecenter = { [unowned self] in self.recenter() }
        view.onEdit = { [unowned self] in self.markDirty() }
        view.onKey = { [unowned self] e in
            let command: Command? = switch e.charactersIgnoringModifiers?.lowercased() {
            case "\u{7f}": .removeSelected
            case "g": .groupAll
            case "u": .ungroupSelected
            case "s": .toggleSnap
            case "a": .addSource
            default: nil
            }
            guard let command else { return false }
            self.perform(command)
            return true
        }

        capture = CaptureService(device: renderer.device)
        syncVirtualScreens()  // recreate the saved layout's virtual screens
        capture.onSourceLost = { [unowned self] _ in Task { await self.refreshSources() } }
        renderer.textureFor = { [unowned self] id in
            self.scene.panel(id)?.source.key.flatMap { self.capture.texture(for: $0) }
        }
        if !CaptureService.hasPermission {
            let pv = PermissionView()
            pv.frame = window.contentView!.bounds
            pv.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(pv)
            permissionView = pv
        }
        Task { await self.refreshSources() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollGlasses()
                await self?.refreshSources()
            }
        }
        pollGlasses()
        NSLog("LumaSpace: \(glasses.status.text)")
        // Mirroring or unplugging the VITURE display moves our borderless window onto the Mac screen;
        // leave the glasses output immediately rather than at the next USB poll.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }

        tracker.recenter(to: .identity)
        if let yaw = ProcessInfo.processInfo.environment["LUMA_SIM_YAW"].flatMap(Double.init) {
            (glasses as? SimulatedGlasses)?.yaw = yaw * .pi / 180
        }
        Snapshot.installIfRequested(renderer: renderer, view: view)
        Demo.runIfRequested(self)
        palette.run = { [unowned self] c in self.perform(c) }
        hotkeys = Hotkeys { [unowned self] action in
            self.grabArming.cancelUntilRelease()  // ⌃⌥ was for a shortcut, not a grab
            switch action {
            case .palette: self.palette.isVisible ? self.palette.hide() : self.showPalette()
            case .command(let c): self.perform(c)
            }
        }
        menuBar = MenuBarController(app: self)

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)

        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveIfDirty() }
        }
    }

    /// LumaSpace lives in the menu bar; closing the preview doesn't quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func showPreview() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPalette() { palette.show(over: glassesWindow ?? window) }

    func setDistance(_ d: Double) {
        distance = min(max(d, SceneLimits.distance.lowerBound), SceneLimits.distance.upperBound)
        scene.setDistance(distance)
        markDirty()
    }

    func applicationWillTerminate(_ n: Notification) {
        dirty = true
        saveIfDirty()
    }

    /// Head orientation for this frame; also cached for picking.
    private func frameHead() -> Quat {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now
        if recenterOnFirstSample, let real = glasses as? VitureGlasses, real.sampleAge != nil {
            recenterOnFirstSample = false
            recenter()
        }
        head = tracker.update(raw: glasses.rawOrientation(), dt: dt)
        updateGrab()
        return head
    }

    /// Where the centre of the view points, in panel degrees.
    var gaze: (yaw: Double, pitch: Double) {
        let d = head.rotate(Vec3(x: 0, y: 0, z: -1))
        return (atan2(-d.x, -d.z) * 180 / .pi, asin(max(-1, min(1, d.y))) * 180 / .pi)
    }

    /// Holding ⌃⌥ grabs the panel at the centre of view; mouse movement moves it.
    /// Polled each frame: global event monitors would need Accessibility permission.
    private func updateGrab() {
        let down = NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]) == [.control, .option]
        let held = grabArming.update(held: down, now: CACurrentMediaTime())
        let mouse = NSEvent.mouseLocation
        switch (held, grabMouse) {
        case (true, nil):
            _ = grab.begin(scene: scene, yaw: gaze.yaw, pitch: gaze.pitch)
            grabMouse = mouse
            renderer.showReticle = true
        case (true, let last?):
            let dx = Double(mouse.x - last.x), dy = Double(mouse.y - last.y)
            if dx != 0 || dy != 0, grab.panelID != nil {
                grab.drag(scene: scene, dx: dx, dy: dy)
                markDirty()
            }
            grabMouse = mouse
        case (false, _?):
            grab.end()
            grabMouse = nil
            renderer.showReticle = false
        case (false, nil):
            break
        }
    }

    /// The single place commands run — menu, palette, shortcuts and keys all come here.
    func perform(_ c: Command) {
        switch c {
        case .recenter: recenter()
        case .applyPreset(let preset): apply(preset)
        case .nudgeDistance(let d): setDistance(distance + d)
        case .resizeSelected(let f):
            if let id = scene.selectedID, let p = scene.panel(id) { scene.resize(id, width: p.width * f) }
        case .adjustLevel(let k, let d): glasses.setLevel(k, (glasses.level(k) ?? 0) + d)
        case .setRate(let r): glasses.setRate(r)
        case .toggleSmoothFollow: tracker.smoothFollow.toggle()
        case .toggleAxisLock(let a):
            if tracker.lockedAxes.contains(a) { tracker.lockedAxes.remove(a) } else { tracker.lockedAxes.insert(a) }
        case .toggleSnap: scene.snap.enabled.toggle()
        case .addSource: addSource()
        case .newVirtualScreen: newVirtualScreen()
        case .arrangeDisplays: arrangeDisplays(for: scene.panels, virtualIDs: virtualDisplays.ids)
        case .removeSelected:
            if let id = scene.selectedID { scene.remove(id); capture.sync(panels: scene.panels); syncVirtualScreens() }
        case .groupAll: scene.group(scene.panels.map(\.id))
        case .ungroupSelected: if let id = scene.selectedID { scene.ungroup(id) }
        case .quit: NSApp.terminate(nil)
        }
        markDirty()
        onStateChange()
    }

    /// Re-lays the current sources out as a preset; Dual and Triple fill empty slots with virtual screens.
    private func apply(_ preset: Preset) {
        let sources = presetSources(preset, current: scene.panels.map(\.source))
        scene.replaceAll(preset.panels(sources: sources, distance: distance))
        syncVirtualScreens()
        Task { await refreshSources() }
    }

    /// Adds a new virtual screen where you're looking.
    private func newVirtualScreen() {
        guard let serial = nextVirtualSerial(in: scene.panels) else {
            NSSound.beep()  // all virtual screens are in use
            return
        }
        let g = gaze
        let id = scene.add(Panel(source: .virtualScreen(serial: serial), yaw: g.yaw, pitch: g.pitch,
                                 distance: distance, width: 1.6 * distance / 2, aspect: 16.0 / 9))
        scene.move(id, toYaw: g.yaw, pitch: g.pitch)
        scene.selectedID = id
        syncVirtualScreens()
    }

    /// Creates and removes macOS displays to match the virtual screen panels. The arrangement is only
    /// redone when screens come or go; moving panels leaves macOS alone ("Arrange Screens Like Panels" does it on demand).
    private func syncVirtualScreens() {
        let serials = Set(scene.panels.compactMap { if case .virtualScreen(let s) = $0.source { s } else { nil } })
        guard virtualDisplays.sync(serials: serials) else { return }
        capture.virtualDisplayIDs = virtualDisplays.ids
        arrangeDisplays(for: scene.panels, virtualIDs: virtualDisplays.ids)
        // A new display takes a moment to reach ScreenCaptureKit.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await self.refreshSources()
        }
    }

    private func addSource() {
        Task {
            await refreshSources()
            picker.present(sources: offeredSources, over: glassesWindow ?? window) { source in
                guard let source else { return }
                let g = self.gaze
                let aspect = source.key.flatMap { self.capture.aspect(of: $0) } ?? 16.0 / 9
                let id = self.scene.add(Panel(source: source, yaw: g.yaw, pitch: g.pitch, distance: self.distance,
                                              width: 1.6 * self.distance / 2, aspect: aspect))
                self.scene.move(id, toYaw: g.yaw, pitch: g.pitch)
                self.scene.selectedID = id
                self.markDirty()
                Task { await self.refreshSources() }
            }
        }
    }

    func recenter() { tracker.recenter(to: glasses.rawOrientation()) }

    private func devicePIDs() -> [Int] {
        guard let sdk else { return [] }
        return findVitureDevicePIDs { sdk.isProductIDValid($0) }
    }

    /// Connects real glasses when they appear; falls back to the simulator after two missed polls.
    func pollGlasses() {
        let pids = devicePIDs()
        if let real = glasses as? VitureGlasses {
            missedPolls = pids.contains(real.pid) ? 0 : missedPolls + 1
            if glassesLost(missedPolls: missedPolls, sampleAge: real.sampleAge,
                           connectedFor: CACurrentMediaTime() - real.connectedAt) {
                NSLog("LumaSpace: glasses disconnected or pose stream stopped")
                useSimulator(reason: "Glasses not connected")  // the next poll reconnects if they're back
            } else if glassesWindow == nil {
                moveOutputToGlasses()  // the display can show up after USB does
            }
            return
        }
        switch chooseGlasses(libraryLoaded: sdk != nil, devicePIDs: pids) {
        case .real(let pid):
            let now = CACurrentMediaTime()
            // While backing off, keep showing the "couldn't be opened" status.
            guard let sdk, bringUp.allowed(pid, now: now) else { return }
            guard let g = VitureGlasses(library: sdk, pid: pid) else {
                bringUp.failed(pid, now: now)
                useSimulator(reason: "Glasses found but couldn't be opened — quit SpaceWalker")
                return
            }
            bringUp.succeeded(pid)
            glasses.stop()
            glasses = g
            g.onEvent = { [unowned self] _ in self.onStateChange() }
            view.simulator = nil
            missedPolls = 0
            moveOutputToGlasses()
            recenterOnFirstSample = true
            onStateChange()
        case .simulated(let reason):
            if glasses.status != .simulated(reason: reason) { useSimulator(reason: reason) }
        }
    }

    /// Leaves the glasses output as soon as the VITURE display goes away or turns into a mirror.
    private func screensChanged() {
        guard let gw = glassesWindow else { return }
        let screen = OutputWindow.usableGlassesScreen()
        if screen == nil || gw.screen != screen {
            NSLog("LumaSpace: VITURE display gone or mirrored; back to the preview")
            moveOutputToPreview()
        } else if let screen, gw.frame != screen.frame {
            gw.setFrame(screen.frame, display: true)  // displays were rearranged
        }
    }

    private func useSimulator(reason: String) {
        glasses.stop()
        let sim = SimulatedGlasses(reason: reason)
        glasses = sim
        view.simulator = sim
        moveOutputToPreview()
        tracker.recenter(to: .identity)
        onStateChange()
    }

    private func moveOutputToGlasses() {
        guard let screen = OutputWindow.usableGlassesScreen() else {
            NSLog("LumaSpace: glasses connected but no extended VITURE display; keeping the preview")
            return
        }
        let w = OutputWindow.fullscreen(on: screen)
        view.removeFromSuperview()
        view.frame = w.contentView!.bounds
        w.contentView!.addSubview(view)
        view.preferredFramesPerSecond = 120
        w.orderFrontRegardless()
        window.orderOut(nil)
        glassesWindow = w
    }

    private func moveOutputToPreview() {
        guard let gw = glassesWindow else { return }
        view.removeFromSuperview()
        view.frame = window.contentView!.bounds
        window.contentView!.addSubview(view, positioned: .below, relativeTo: nil)
        view.preferredFramesPerSecond = 60
        gw.orderOut(nil)
        glassesWindow = nil
        window.makeKeyAndOrderFront(nil)
    }

    /// Re-reads available windows/displays, flags lost sources and keeps capture streams in sync.
    func refreshSources() async {
        guard CaptureService.hasPermission else { return }
        if let pv = permissionView { pv.removeFromSuperview(); permissionView = nil }
        capture.glassesDisplayID = OutputWindow.glassesScreen()
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        let r = await capture.refresh()
        offeredSources = r.offered
        // A fresh layout of placeholders starts by showing the main display.
        if scene.panels.allSatisfy({ $0.source.key == nil }), let first = scene.panels.first,
           let display = r.offered.first(where: { if case .display = $0 { true } else { false } }) {
            var p = first
            p.source = display
            scene.replaceAll([p] + scene.panels.dropFirst())
            markDirty()
        }
        scene.updateAvailability(available: r.existing)
        capture.sync(panels: scene.panels)
    }

    func markDirty() { dirty = true }

    private func loadLayout() {
        let f = store.load()
        scene.replaceAll(f.panels)
        distance = f.distance
        tracker.smoothFollow = f.smoothFollow
        tracker.lockedAxes = Set(f.lockedAxes)
    }

    private func saveIfDirty() {
        guard dirty else { return }
        dirty = false
        let f = LayoutFile(panels: scene.panels, distance: distance, smoothFollow: tracker.smoothFollow,
                           lockedAxes: Axis.allCases.filter { tracker.lockedAxes.contains($0) })
        do { try store.save(f) } catch { NSLog("LumaSpace: could not save layout: \(error)") }
    }
}
