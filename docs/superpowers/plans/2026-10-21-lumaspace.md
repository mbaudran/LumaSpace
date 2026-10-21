# LumaSpace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that shows captured windows/displays as head-tracked, freely laid-out virtual screens on VITURE Luma glasses, with a menu bar and command palette for quick control.

**Architecture:** A platform-free `LumaCore` library (pose math, head tracker, layout model, presets, persistence, commands, glasses protocol + simulator) is checked by an executable `LumaChecks`. The `LumaSpace` executable adds AppKit, Metal (runtime-compiled shaders), ScreenCaptureKit, Carbon hotkeys and a `dlopen` bridge to `libglasses.dylib`. A script wraps the binary into an ad-hoc signed `.app`.

**Tech Stack:** Swift 6.4 (Command Line Tools only), SwiftPM, AppKit, Metal, MetalKit, ScreenCaptureKit, IOKit, Carbon (hotkeys), VITURE Glasses SDK (C, loaded at runtime).

**Spec:** `docs/superpowers/specs/2026-10-21-lumaspace-design.md`

## Global Constraints

- Build with SwiftPM only; never call `xcodebuild`. Build and run with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk` (the 27 SDK makes Apple macros need Xcode plugins).
- No Swift macros anywhere: no `#expect`/`@Test`, no `@Observable`, no SwiftUI `@State`. XCTest is unavailable. Tests are plain functions run by `swift run LumaChecks`, which exits 1 on any failure.
- `Package.swift`: `// swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`, Swift 6 language mode.
- Metal shaders live in a Swift string and are compiled with `MTLDevice.makeLibrary(source:options:)`.
- SDK is never linked at build time and never committed: `vendor/` is git-ignored. Runtime lookup order for `libglasses.dylib`: `$LUMA_SDK_PATH`, `<app>/Contents/Frameworks/`, `vendor/viture-sdk/aarch64/` relative to the current directory.
- Luma = Gen1, 3DoF. USB VID `0x35CA`. Pose callback data `[roll, pitch, yaw, qw, qx, qy, qz]`, North-West-Up, delivered on an SDK thread.
- Luma display: 1920×1080, diagonal FOV 52°.
- Do not reproduce SpaceWalker code or assets.
- Layout file: `~/Library/Application Support/LumaSpace/layout.json`.
- Bundle id `dev.lumaspace.app`, app name `LumaSpace`.

## Review Focus

1. **Infinite mirror:** capturing a display that contains LumaSpace's own output window (or the glasses display itself) must never happen — own windows are excluded and the glasses display is not offered as a source. Test in Task 9.
2. **Source disappears:** a captured window closes or a display unplugs mid-session → the panel stays in place showing "Source unavailable", no crash. Test in Task 3.
3. **Corrupt or missing layout file:** invalid JSON, wrong schema version or missing file → default "single" preset loads, the bad file is renamed `layout.json.bad`. Test in Task 5.
4. **Glasses absent, unplugged or SDK missing:** app starts in simulator mode; unplug mid-session → falls back to simulator without losing layout; replug → reconnects. Test in Task 6 (selector logic).
5. **Out-of-range manipulation:** dragging past ±180° yaw, beyond ±75° pitch, distance or size to 0 → yaw wraps, pitch/distance/size clamp. Test in Task 3.

---

## File Structure

```
lumaspace/
  Package.swift
  scripts/bundle.sh                  # build .app, copy dylib, Info.plist, codesign
  Resources/Info.plist
  Sources/LumaCore/
    Quat.swift                       # quaternion + vector math, NWU→render conversion
    HeadTracker.swift                # recenter, smooth follow, axis locks
    Panel.swift                      # Panel, PanelSource, angular extents
    SpatialScene.swift               # panel collection: add/move/resize/hit-test/clamp/availability
    Snapping.swift                   # grid + edge snapping, groups
    Presets.swift                    # preset layouts
    LayoutStore.swift                # JSON persistence
    Glasses.swift                    # GlassesLink protocol, GlassesStatus, LevelKind
    SimulatedGlasses.swift
    GlassesSelector.swift            # choose real vs simulated, reconnect decisions
    Commands.swift                   # Command enum, palette matching
    CaptureSources.swift             # pure filtering of displays/windows offered as sources
  Sources/LumaChecks/
    Harness.swift                    # check(), expectEqual(), expectNear(), exit code
    main.swift                       # calls every *Checks() function
    QuatChecks.swift ... (one file per LumaCore file)
  Sources/LumaSpace/
    main.swift                       # NSApplication bootstrap
    AppController.swift              # owns everything, frame loop, wiring
    Renderer.swift                   # Metal pipeline, shader source string
    Shaders.swift
    OutputWindow.swift               # preview window or fullscreen on glasses display
    InputController.swift            # mouse/keyboard → simulated head + layout edits
    CaptureService.swift             # ScreenCaptureKit → MTLTexture per panel
    PermissionView.swift             # screen-recording explainer
    MenuBarController.swift
    PaletteWindow.swift
    Hotkeys.swift                    # Carbon RegisterEventHotKey
    VitureGlasses.swift              # dlopen bridge + IOKit enumeration
  README.md
```

---

### Task 1: Package skeleton, check harness, quaternion math

**Files:**
- Create: `Package.swift`, `Sources/LumaCore/Quat.swift`, `Sources/LumaChecks/Harness.swift`, `Sources/LumaChecks/main.swift`, `Sources/LumaChecks/QuatChecks.swift`, `Sources/LumaSpace/main.swift` (prints "LumaSpace" and exits; replaced in Task 8)

**Interfaces:**
- Produces: `struct Vec3: Equatable, Codable { x, y, z: Double }` with `+ - *scalar`, `dot`, `length`, `normalized`.
- `struct Quat: Equatable, Codable { w, x, y, z: Double }` with `static let identity`, `init(axis: Vec3, angle: Double)` (radians), `*` (Hamilton product), `conjugate`, `normalized`, `rotate(_ v: Vec3) -> Vec3`, `slerp(_ a: Quat, _ b: Quat, _ t: Double) -> Quat`, `var yawPitchRoll: (yaw: Double, pitch: Double, roll: Double)` (radians; yaw about +Y, pitch about +X, roll about +Z, applied yaw·pitch·roll), `init(yaw:pitch:roll:)`.
- `func renderQuat(fromNWU w: Double, _ x: Double, _ y: Double, _ z: Double) -> Quat` — render frame is right-handed, X right, Y up, −Z forward. NWU→render vector map is `r = (−y_n, z_n, −x_n)` (a proper rotation), so the quaternion is `Quat(w: w, x: -y, y: z, z: -x)`.
- Harness: `func check(_ name: String, _ body: () throws -> Void)`, `func expectEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "")`, `func expectNear(_ a: Double, _ b: Double, tol: Double = 1e-6, _ msg: String = "")`, `func expect(_ cond: Bool, _ msg: String = "")`, `func finishChecks() -> Never` (prints `N passed, M failed`, exits 1 if M > 0).
- Package targets: `LumaCore` (library), `LumaChecks` (executable, depends on LumaCore), `LumaSpace` (executable, depends on LumaCore; linker settings for frameworks `Metal`, `MetalKit`, `ScreenCaptureKit`, `IOKit`, `Carbon`, `AppKit`, `CoreVideo`).

- [ ] **Step 1: Write failing checks** in `QuatChecks.swift` as `func quatChecks()`:
  - `rotate`: `Quat(axis: (0,1,0), angle: .pi/2).rotate((0,0,-1))` ≈ `(-1,0,0)` (turning left 90° makes forward point left).
  - `q * q.conjugate` ≈ identity for `Quat(yaw: 0.3, pitch: -0.2, roll: 0.1)`.
  - `yawPitchRoll` round-trips `(0.4, -0.3, 0.2)` within 1e-9.
  - `slerp(identity, Quat(axis:(0,1,0), angle: 1.0), 0.5).yawPitchRoll.yaw` ≈ 0.5.
  - NWU: a head yawing left 90° in NWU is a +90° rotation about +Z_n = `(w: cos45°, x:0, y:0, z: sin45°)`; `renderQuat(fromNWU:)` of it rotates render forward `(0,0,-1)` to ≈ `(-1,0,0)`.
  - NWU nose-up 30° is a rotation of −30° about +Y_n (West): `Quat(axis: (0,1,0), angle: -.pi/6)` taken as NWU components, converted, rotates `(0,0,-1)` to y ≈ `0.5`.
- [ ] **Step 2: Run** `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift run LumaChecks` — expected: compile failure (types undefined).
- [ ] **Step 3: Implement** `Quat.swift` and the harness. `finishChecks()` is the last line of `main.swift`.
- [ ] **Step 4: Run** the same command — expected: `6 passed, 0 failed`, exit 0. Also `swift build` succeeds for all targets.
- [ ] **Step 5: Commit** `feat: package skeleton, check harness, quaternion math`.

### Task 2: HeadTracker (recenter, smooth follow, axis locks)

**Files:** Create `Sources/LumaCore/HeadTracker.swift`, `Sources/LumaChecks/HeadTrackerChecks.swift`.

**Interfaces:**
- Consumes: `Quat`.
- Produces: `enum Axis: String, Codable, CaseIterable { case yaw, pitch, roll }`; `final class HeadTracker` with
  - `var smoothFollow: Bool` (default false), `var followRate: Double = 2.0` (per second), `var lockedAxes: Set<Axis> = []`
  - `func recenter(to raw: Quat)` — stores the yaw-only part of `raw` as the reference (keeps world level).
  - `func update(raw: Quat, dt: Double) -> Quat` — returns the head orientation relative to the reference: `relative = ref⁻¹ · raw`; then zero each locked axis in yaw/pitch/roll and rebuild; when `smoothFollow`, maintain an `anchor` quat that slerps toward `relative` by `1 − exp(−followRate·dt)` and return `anchor⁻¹ · relative` (screens trail the head and settle back in front).
  - First `update` without a prior `recenter` recenters automatically.

- [ ] **Step 1: Failing checks** (`headTrackerChecks()`):
  - after `recenter(to: Quat(yaw: 0.8, pitch: 0, roll: 0))`, `update(raw: same, dt: 0.016)` ≈ identity.
  - recenter with `raw = Quat(yaw: 0.5, pitch: 0.3, roll: 0)` keeps pitch: `update(raw: same).yawPitchRoll.pitch` ≈ 0.3, yaw ≈ 0.
  - `lockedAxes = [.yaw]`: `update(raw: Quat(yaw: 0.6, pitch: 0.2, roll: 0))` → yaw ≈ 0, pitch ≈ 0.2.
  - smooth follow: hold `raw = Quat(yaw: 0.5…)` for 5 s in 0.016 s steps → returned yaw < 0.01; after the first step it is > 0.45.
  - no prior recenter: first `update(raw: Quat(yaw: 1.2…))` ≈ identity.
- [ ] **Step 2: Run** checks — expected FAIL (undefined).
- [ ] **Step 3: Implement** `HeadTracker`.
- [ ] **Step 4: Run** — all pass.
- [ ] **Step 5: Commit** `feat: head tracker with recenter, smooth follow, axis locks`.

### Task 3: Panel model and SpatialScene

**Files:** Create `Sources/LumaCore/Panel.swift`, `Sources/LumaCore/SpatialScene.swift`, `Sources/LumaChecks/SceneChecks.swift`.

**Interfaces:**
- Produces:
  - `enum PanelSource: Codable, Hashable { case display(id: UInt32, name: String), window(id: UInt32, app: String, title: String), placeholder(String) }` with `var key: SourceKey?` (nil for placeholders) and `var label: String`
  - `enum SourceKey: Hashable { case display(UInt32), window(UInt32) }` — identity for capture/availability, so window title changes don't break matching
  - `struct Panel: Codable, Identifiable, Equatable { id: UUID; source: PanelSource; yaw: Double; pitch: Double` (degrees, panel centre as seen from the head) `; distance: Double` (m) `; width: Double` (m) `; aspect: Double` (w/h) `; groupID: UUID?; var available: Bool = true` (not persisted: `CodingKeys` omit it) `}`
  - `Panel` helpers: `var height: Double`, `var angularWidth: Double` = `2·atan(width/2/distance)` in degrees, `var angularHeight`, `func contains(yaw: Double, pitch: Double) -> Bool` (angular rectangle, yaw difference wrapped to (−180, 180]), `func worldCenter() -> Vec3` (render frame: yaw about +Y with yaw>0 = left, pitch>0 = up, −Z forward).
  - `struct SceneLimits { static let pitch = -75.0...75.0; distance = 0.5...10.0; width = 0.2...12.0 }`
  - `func wrapYaw(_ d: Double) -> Double` → (−180, 180].
  - `final class SpatialScene { private(set) var panels: [Panel]; var selectedID: UUID?`
    - `@discardableResult func add(_ p: Panel) -> UUID`, `func remove(_ id: UUID)`
    - `func move(_ id: UUID, toYaw: Double, pitch: Double)` (wraps/clamps; group handled in Task 4)
    - `func resize(_ id: UUID, width: Double)` (clamps), `func setDistance(_ d: Double)` (all panels, clamped)
    - `func hitTest(yaw: Double, pitch: Double) -> UUID?` — nearest panel (smallest distance) containing the direction; topmost on ties = last added.
    - `func updateAvailability(available: Set<SourceKey>)` — sets `available` false for panels whose `source.key` is absent; placeholders stay available. Never removes panels.
    - `func replaceAll(_ panels: [Panel])` `}`

- [ ] **Step 1: Failing checks** (`sceneChecks()`):
  - `angularWidth` of width 1.0 m at distance 1.0 m ≈ 53.13°.
  - `contains`: panel at yaw 170, angular width ~20 → contains yaw −175 (wrap).
  - `move` to yaw 190 → stored −170; pitch 120 → 75; `resize` width 0 → 0.2; `setDistance(0)` → 0.5 (Review Focus 5).
  - `hitTest`: two overlapping panels at same direction, distances 2 and 1 → returns the 1 m one; empty direction → nil.
  - `updateAvailability([])` on a `.window(id: 9, …)` panel → `available == false`, `panels.count` unchanged; then `updateAvailability([.window(9)])` → `true` even though the title differs (Review Focus 2).
  - Codable round-trip of a panel preserves everything except `available`, which decodes as `true`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: panel model and spatial scene`.

### Task 4: Snapping and groups

**Files:** Create `Sources/LumaCore/Snapping.swift`; modify `SpatialScene.swift` (move applies to groups); create `Sources/LumaChecks/SnappingChecks.swift`.

**Interfaces:**
- Consumes: `SpatialScene`, `Panel`.
- Produces:
  - `struct SnapSettings { var enabled = true; var grid = 5.0; var edgeThreshold = 2.0 }` (degrees)
  - `func snapped(_ p: Panel, toYaw: Double, pitch: Double, others: [Panel], settings: SnapSettings) -> (yaw: Double, pitch: Double)` — first, if any edge of `p` (left/right in yaw, top/bottom in pitch) at the target lies within `edgeThreshold` of an edge of another panel (abutting: left↔right, top↔bottom; aligning: left↔left, centre↔centre), snap that axis to make them touch/align; else round the axis to `grid`. Axes snap independently.
  - `SpatialScene`: `var snap = SnapSettings()`, `func group(_ ids: [UUID])` (assigns one new groupID), `func ungroup(_ id: UUID)`, and `move` now snaps the dragged panel against panels outside its group, then applies the same delta to every member of its group.

- [ ] **Step 1: Failing checks** (`snappingChecks()`):
  - two panels at distance 2 m, width 1 m (angular ≈ 28.07°). A at yaw 0 (yaw > 0 is left, so A's right edge is at −14.04). Moving B to yaw −29.0 puts B's left edge 0.93° from A's right edge → B yaw ≈ −28.07, edges abut.
  - moving B to yaw −60.3 with no edge nearby → −60.0 (grid).
  - `snap.enabled = false` → exact target kept.
  - grouped A+B, move A by +10° yaw → B moved by the same +10°.
  - `ungroup(B)` then move A → B unchanged.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: edge/grid snapping and panel groups`.

### Task 5: Presets and LayoutStore

**Files:** Create `Sources/LumaCore/Presets.swift`, `Sources/LumaCore/LayoutStore.swift`, `Sources/LumaChecks/LayoutChecks.swift`.

**Interfaces:**
- Consumes: `Panel`, `PanelSource`, `SpatialScene`.
- Produces:
  - `enum Preset: String, CaseIterable, Codable { case single, dual, triple, stacked, ultrawide, coding }` with `var title: String` ("Single", "Dual", "Triple", "Stacked", "Ultrawide", "Coding") and `func panels(sources: [PanelSource], distance: Double) -> [Panel]`. Default panel width 1.6 m, aspect 16/9 at distance 2.0. Layouts: single = 1 centred; dual = 2 side by side abutting; triple = 3 abutting; stacked = 3 abutting with the centre one top, two below; ultrawide = 1 panel aspect 32/9, width 3.2 m; coding = portrait (aspect 9/16, width 0.9) · landscape · portrait abutting. Sources fill in order; missing sources become `.placeholder("Screen N")`. All presets share a fresh `groupID`.
  - `struct LayoutFile: Codable { var version: Int` (= 1) `; var panels: [Panel]; var distance: Double; var smoothFollow: Bool; var lockedAxes: [Axis] }`
  - `struct LayoutStore { let url: URL; func load() -> LayoutFile; func save(_ f: LayoutFile) throws }` — `load` returns `LayoutFile.default` (= single preset with one placeholder, distance 2.0) when the file is missing; when it can't be decoded or `version != 1` it renames the file to `layout.json.bad` (replacing an old one) and returns the default. `save` writes atomically, creating the directory.
  - `static func defaultURL() -> URL` = Application Support/LumaSpace/layout.json.

- [ ] **Step 1: Failing checks** (`layoutChecks()`), using a temp dir:
  - `Preset.triple.panels(sources: [], distance: 2)` → 3 placeholders, middle yaw 0, neighbours abut (right edge of left one == left edge of middle within 1e-6), all share one groupID.
  - `Preset.coding` → middle aspect 16/9, outer two aspect 9/16.
  - save then load → equal `LayoutFile`.
  - missing file → default (1 panel, distance 2).
  - file containing `{not json` → default returned and `layout.json.bad` exists (Review Focus 3).
  - `{"version": 99, ...}` valid JSON → default + `.bad`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: layout presets and persistence`.

### Task 6: GlassesLink, simulator, selector

**Files:** Create `Sources/LumaCore/Glasses.swift`, `SimulatedGlasses.swift`, `GlassesSelector.swift`, `Sources/LumaChecks/GlassesChecks.swift`.

**Interfaces:**
- Consumes: `Quat`.
- Produces:
  - `enum LevelKind { case brightness, volume }`
  - `enum GlassesStatus: Equatable { case simulated(reason: String), connected(name: String), disconnected }`
  - `enum DisplayRate: Int, CaseIterable { case hz60 = 60, hz90 = 90, hz120 = 120 }`
  - `protocol GlassesLink: AnyObject { var status: GlassesStatus { get }; func rawOrientation() -> Quat` (render frame, thread-safe) `; func level(_ k: LevelKind) -> Int?; func maxLevel(_ k: LevelKind) -> Int?; func setLevel(_ k: LevelKind, _ v: Int); func setRate(_ r: DisplayRate); var onEvent: ((GlassesEvent) -> Void)? { get set }; func stop() }`
  - `enum GlassesEvent { case levelChanged(LevelKind, Int), disconnected }`
  - `final class SimulatedGlasses: GlassesLink` — `var yaw, pitch, roll: Double` (radians, set by input), levels stored in memory with max 8 (brightness) and 8 (volume), `setLevel` clamps to `0...max`, status `.simulated(reason:)` given at init.
  - `enum GlassesChoice: Equatable { case real(pid: Int), simulated(reason: String) }` and `func chooseGlasses(libraryLoaded: Bool, devicePIDs: [Int]) -> GlassesChoice` — no library → `.simulated(reason: "VITURE SDK not found")`; no device → `.simulated(reason: "Glasses not connected")`; else `.real(pid: devicePIDs.first!)` (deduplicated order preserved).

- [ ] **Step 1: Failing checks** (`glassesChecks()`):
  - `chooseGlasses(libraryLoaded: false, devicePIDs: [0x1101])` → simulated "VITURE SDK not found".
  - `(true, [])` → simulated "Glasses not connected" (Review Focus 4).
  - `(true, [0x1101, 0x1101])` → `.real(pid: 0x1101)`.
  - `SimulatedGlasses`: `setLevel(.brightness, 20)` → `level(.brightness) == 8`; `-3` → 0; `rawOrientation()` with yaw 0.5 has `yawPitchRoll.yaw ≈ 0.5`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: glasses protocol, simulator and selector`.

### Task 7: Commands and palette matching

**Files:** Create `Sources/LumaCore/Commands.swift`, `Sources/LumaChecks/CommandChecks.swift`.

**Interfaces:**
- Consumes: `Preset`, `LevelKind`, `DisplayRate`, `Axis`.
- Produces:
  - `enum Command: Hashable { case recenter, applyPreset(Preset), nudgeDistance(Double), adjustLevel(LevelKind, Int), setRate(DisplayRate), toggleSmoothFollow, toggleAxisLock(Axis), toggleSnap, addSource, removeSelected, groupAll, ungroupSelected, quit }` with `var title: String` (e.g. "Recenter", "Layout: Triple", "Closer", "Farther", "Brightness +", "Brightness −", "Volume +", "Volume −", "Refresh 90 Hz", "Smooth Follow", "Lock Yaw", "Snapping", "Add Window or Display…", "Remove Selected Screen", "Group All Screens", "Ungroup Selected", "Quit LumaSpace") and `var keywords: [String]`.
  - `static var all: [Command]` — every preset, distance ±0.25 m, levels ±1, every rate, every axis, and the rest.
  - `func paletteMatches(_ query: String, in commands: [Command]) -> [Command]` — case/diacritic-insensitive subsequence match on title + keywords; empty query returns all in original order; ranking: prefix of title > word-prefix > subsequence; ties keep original order.

- [ ] **Step 1: Failing checks** (`commandChecks()`):
  - `paletteMatches("", in: Command.all) == Command.all`.
  - `paletteMatches("tri", …).first == .applyPreset(.triple)`.
  - `paletteMatches("rec", …).first == .recenter`.
  - `paletteMatches("bri+", …)` contains `.adjustLevel(.brightness, 1)`.
  - `paletteMatches("zzzz", …)` is empty.
  - Keyword: `paletteMatches("center", …)` contains `.recenter`.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — pass.
- [ ] **Step 5: Commit** `feat: commands and palette matching`.

### Task 8: App shell, Metal renderer, simulator preview (Stage 1)

**Files:** Create `Sources/LumaSpace/{main.swift, AppController.swift, Renderer.swift, Shaders.swift, OutputWindow.swift, InputController.swift}`, `Resources/Info.plist`, `scripts/bundle.sh`.

**Interfaces:**
- Consumes: `HeadTracker`, `SpatialScene`, `SimulatedGlasses`, `LayoutStore`, `Preset`.
- Produces:
  - `final class Renderer: NSObject, MTKViewDelegate` — `init?(view: MTKView)`; `var scene: SpatialScene`; `var headOrientation: () -> Quat`; `var textureFor: (UUID) -> MTLTexture?`. Each frame: projection from vertical FOV derived from 52° diagonal at the view's aspect (≈ 26.9° vertical at 16:9), view = inverse(head); draws each panel as a textured quad facing the origin at `worldCenter()`, back to front; a panel with no texture draws a dark rounded placeholder with its label (label rendered via `NSAttributedString` → `CGContext` → cached texture); unavailable panels draw "Source unavailable"; the selected panel gets a 4 px accent outline. Background clear colour black (transparent on the glasses).
  - `Shaders.swift`: `let shaderSource: String` with `panelVertex`/`panelFragment` (textured quad with rounded-corner alpha via signed-distance in the fragment shader, outline when `selected`).
  - `final class OutputWindow` — `static func preview() -> NSWindow` (1280×720 titled "LumaSpace — Simulator") and `static func fullscreen(on screen: NSScreen) -> NSWindow` (borderless, `.screenSaver` level − 1, `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary]`). `static func glassesScreen() -> NSScreen?` — first `NSScreen` whose `localizedName` contains "VITURE" (case-insensitive).
  - `final class InputController` — in simulator mode: right-drag (or ⌥-drag) changes `SimulatedGlasses.yaw/pitch` at 0.25°/pt; left click → `scene.hitTest` on the ray through the cursor (cursor → head-relative yaw/pitch using the projection, then rotated by the head orientation); left-drag moves the selected panel; scroll resizes the selected panel (±5 %); `R` recenters.
  - `AppController.start()` — loads layout, builds scene, creates simulator glasses, preview window + MTKView at 60 fps (`preferredFramesPerSecond = 120` when on the glasses screen), saves layout on change (debounced 1 s) and on quit.
  - `scripts/bundle.sh [--install]` — `swift build -c release` with the 26 SDK, assembles `build/LumaSpace.app` (`Contents/MacOS/LumaSpace`, `Contents/Info.plist`, `Contents/Frameworks/libglasses.dylib` copied from `vendor/viture-sdk/aarch64` if present, rpath `@executable_path/../Frameworks`), `codesign --force --deep -s -`. `--install` copies to `/Applications`.
  - `Info.plist`: `CFBundleIdentifier dev.lumaspace.app`, `CFBundleName LumaSpace`, `LSMinimumSystemVersion 14.0`, `LSUIElement true` (menu bar app), `NSScreenCaptureUsageDescription` "LumaSpace shows your windows and displays as virtual screens in your glasses."

- [ ] **Step 1: Build** `scripts/bundle.sh` — expected `build/LumaSpace.app` produced, `codesign -v build/LumaSpace.app` succeeds.
- [ ] **Step 2: Run** `open build/LumaSpace.app`; take a screenshot (`screencapture -l <windowid>` or `screencapture -x`) — expected: preview window with one placeholder panel "Screen 1" centred on black.
- [ ] **Step 3: Verify head motion**: drive simulated yaw from a debug env var `LUMA_SIM_YAW=20` at launch → screenshot shows the panel shifted right (head turned left, world stays). Confirms sign conventions end to end.
- [ ] **Step 4: Verify layout reload**: quit, check `layout.json` exists and is valid JSON (`python3 -m json.tool`).
- [ ] **Step 5: Commit** `feat: app shell, Metal renderer and simulator preview`.

### Task 9: Screen capture into panels

**Files:** Create `Sources/LumaCore/CaptureSources.swift`, `Sources/LumaChecks/CaptureSourceChecks.swift`, `Sources/LumaSpace/CaptureService.swift`, `Sources/LumaSpace/PermissionView.swift`; modify `AppController.swift`.

**Interfaces:**
- Consumes: `PanelSource`, `SpatialScene.updateAvailability`, `Renderer.textureFor`.
- Produces:
  - LumaCore: `struct DisplayInfo { id: UInt32; name: String }`, `struct WindowInfo { id: UInt32; app: String; title: String; ownerPID: Int32; layer: Int; onScreen: Bool }`, availability is reported to the scene as `Set<SourceKey>`; `func offeredSources(displays: [DisplayInfo], windows: [WindowInfo], glassesDisplayID: UInt32?, ownPID: Int32) -> [PanelSource]` — excludes the glasses display, all windows owned by `ownPID`, windows with `layer != 0`, empty titles, and off-screen windows; displays first, then windows sorted by app then title.
  - App: `final class CaptureService` — `func refreshSources() async -> [PanelSource]` (uses `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` then `offeredSources`); `func sync(panels: [Panel])` starts one `SCStream` per distinct available source and stops streams no panel uses; display streams use `SCContentFilter(display:excludingWindows:)` with every LumaSpace window excluded; frames → `CVMetalTextureCache` → `MTLTexture`, latest per source, read by `texture(for panelID:)`; stream errors mark the source unavailable via the scene. Capture size = source pixel size capped at 2560 px wide, `minimumFrameInterval` 1/60 s, `showsCursor = true`.
  - `PermissionView`: if `CGPreflightScreenCaptureAccess()` is false, the preview shows an explainer panel with a button calling `CGRequestScreenCaptureAccess()` and opening `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.

- [ ] **Step 1: Failing checks** (`captureSourceChecks()`):
  - glasses display id 7 among displays [1 "Built-in", 7 "VITURE"] → only display 1 offered (Review Focus 1).
  - a window with `ownerPID == ownPID` is excluded (Review Focus 1); `layer 25` excluded; empty title excluded.
  - ordering: displays before windows; windows sorted by app, then title.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** core function. **Step 4: Run** — pass.
- [ ] **Step 5: Implement** `CaptureService` + permission flow; set the default preset's first source to the main display.
- [ ] **Step 6: Verify**: bundle, grant permission, launch → screenshot shows the main display live inside the panel and no recursive mirror of the preview window.
- [ ] **Step 7: Verify source loss**: add a TextEdit window as a panel, quit TextEdit → panel shows "Source unavailable", app keeps running (Review Focus 2).
- [ ] **Step 8: Commit** `feat: capture windows and displays into panels`.

### Task 10: Free layout editing (Stage 2)

**Files:** Modify `InputController.swift`, `AppController.swift`; create `Sources/LumaSpace/SourcePicker.swift`.

**Interfaces:**
- Consumes: `SpatialScene` (move/resize/group/remove/snap), `CaptureService.refreshSources`, `Preset`.
- Produces: `final class SourcePicker` — `func present(sources: [PanelSource], completion: (PanelSource?) -> Void)`: a floating `NSPanel` list over the output window (search field + table, ↑/↓/↩/⎋). New panels are placed at the current gaze direction (head yaw/pitch), then snapped.
- Interaction in glasses mode (the preview window keeps Task 8's direct mouse editing): with **⌃⌥ held**, cursor movement moves a gaze reticle (via a global `NSEvent` monitor); click selects; drag moves; scroll resizes; `⌫` removes the selected panel; `G` groups all; `U` ungroups selected; `S` toggles snapping. Edits save via the debounced store.

- [ ] **Step 1: Implement** picker and the interactions above.
- [ ] **Step 2: Verify** in simulator via scripted input (`cliclick` is not installed; use `CGEvent` posting from a small `swift` script in the scratchpad): add 3 sources, drag one next to another → screenshot shows them abutting (snap), relaunch → same positions. If event posting is blocked by Accessibility permissions, verify the snap through `layout.json` values and report the visual check as not done.
- [ ] **Step 3: Verify** clamping by dragging far up → panel stops at 75° pitch (Review Focus 5).
- [ ] **Step 4: Commit** `feat: free layout editing with source picker`.

### Task 11: Quick controls (Stage 3)

**Files:** Create `Sources/LumaSpace/{MenuBarController.swift, PaletteWindow.swift, Hotkeys.swift}`; modify `AppController.swift` (single `perform(_ c: Command)` entry point).

**Interfaces:**
- Consumes: `Command`, `paletteMatches`, `GlassesLink`, `HeadTracker`, `SpatialScene`, `Preset`.
- Produces:
  - `AppController.perform(_ c: Command)` — the only place commands are executed (menu, palette and hotkeys all call it).
  - `MenuBarController` — `NSStatusItem` (SF Symbol `eyeglasses`); menu: status line (`GlassesStatus` text), Layout submenu (presets, ✓ none), Brightness and Volume slider rows (custom `NSView` with `NSSlider`, range `0...maxLevel`), Distance slider (0.5–10 m), Refresh submenu (disabled in simulator), Smooth Follow, Lock submenu (yaw/pitch/roll), Snapping, Recenter, Add Window or Display…, Open Preview, Quit.
  - `PaletteWindow` — borderless `NSPanel`, 560×360, centred on the output window's screen, vibrancy material, search field + list showing `title` and shortcut; ↑/↓/↩ runs `perform`, ⎋ closes; closes on resign key.
  - `Hotkeys` — Carbon `RegisterEventHotKey`: ⌃⌥Space palette, ⌃⌥R recenter, ⌃⌥1…6 presets in `Preset.allCases` order, ⌃⌥= closer, ⌃⌥- farther, ⌃⌥F smooth follow, ⌃⌥A add source, ⌃⌥B / ⌃⌥⇧B brightness up/down. A registration failure is logged and shown in the menu as "Shortcut ⌃⌥X unavailable", never fatal.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Verify** ⌃⌥Space opens the palette over the preview, typing "tri" + ↩ applies Triple (screenshot).
- [ ] **Step 3: Verify** menu brightness slider changes `SimulatedGlasses.level(.brightness)` (log line) and ⌃⌥R recenters.
- [ ] **Step 4: Commit** `feat: menu bar, command palette and global shortcuts`.

### Task 12: VITURE SDK bridge and glasses output (Stage 4)

**Files:** Create `Sources/LumaSpace/VitureGlasses.swift`; modify `AppController.swift` (selector + reconnect), `OutputWindow.swift` usage.

**Interfaces:**
- Consumes: `GlassesLink`, `chooseGlasses`, `renderQuat(fromNWU:)`, `HeadTracker`, `OutputWindow.glassesScreen()`.
- Produces:
  - `final class VitureLibrary` — `static func load() -> VitureLibrary?` using the Global Constraints lookup order; `dlsym` binds, as `@convention(c)` typed function pointers: `xr_device_provider_create(Int32)`, `_initialize(handle, nil, cacheDir)`, `_start`, `_stop`, `_shutdown`, `_destroy`, `_register_state_callback`, `_register_imu_pose_callback`, `_open_imu(handle, 1 /*POSE*/, freq)`, `_close_imu`, `_is_product_id_valid`, `_is_product_support_imu_frequency`, `_get_market_name`, `_get/_set_brightness_level`, `_get/_set_volume_level`, `_get_value_max` (ids 0 brightness, 1 volume), `_set_display_mode` (60 Hz `0x31`, 90 Hz `0x33`, 120 Hz `0x34`), `_set_log_level`. Missing symbol → `load()` returns nil with the symbol name logged.
  - `func findVitureDevicePIDs(isValid: (Int32) -> Bool) -> [Int]` — IOKit `IOServiceMatching(kIOUSBDeviceClassName)`, read `idVendor`/`idProduct`, keep VID `0x35CA` with `isValid`, deduplicate.
  - `final class VitureGlasses: GlassesLink` — `init?(library:, pid:)` runs create → initialize (cache dir Application Support/LumaSpace/sdk-cache) → register callbacks → start → `open_imu(POSE, highest supported of 500/240/120 Hz)`. C callbacks are global `@convention(c)` functions that forward to a single `static weak var current`; pose stored behind `OSAllocatedUnfairLock`, converted with `renderQuat(fromNWU: d[3], d[4], d[5], d[6])`. State callback ids 0/1 → `.levelChanged`. `stop()` reverses the lifecycle (close_imu → stop → shutdown → destroy). Status `.connected(name: market name)`.
  - `AppController`: at launch and every 2 s while simulated, run `chooseGlasses(libraryLoaded:, devicePIDs:)`; on `.real` create `VitureGlasses`, move output to `fullscreen(on: glassesScreen())` (preview stays available from the menu), recenter. A disconnect (device PID gone for 2 polls or USB error) → `stop()`, back to simulator + preview, layout untouched (Review Focus 4).

- [ ] **Step 1: Add the probe first** — `main.swift` handles `--probe-sdk` (load library, enumerate, print, exit) by calling `VitureLibrary.load()` and `findVitureDevicePIDs`; build → expected compile failure (types undefined). The probe is the test: `LUMA_SDK_PATH=vendor/viture-sdk/aarch64/libglasses.dylib build/LumaSpace.app/Contents/MacOS/LumaSpace --probe-sdk` must print `sdk: loaded, devices: 0`, and with `LUMA_SDK_PATH=/nonexistent` (and no bundled copy, i.e. run `.build/release/LumaSpace` from `/tmp`) `sdk: missing`.
- [ ] **Step 2: Implement** `VitureLibrary`, `findVitureDevicePIDs`, `VitureGlasses`, reconnect logic.
- [ ] **Step 3: Run** both probe commands — expected outputs as above; then launch the app normally → menu shows "Simulator — Glasses not connected".
- [ ] **Step 4: Commit** `feat: VITURE SDK bridge and glasses output`.
- [ ] **Step 5: Hardware test (friend):** checklist in README — glasses detected by name, screens stay fixed when turning head, ⌃⌥R recenters, brightness buttons update the menu, unplug → simulator, replug → back. Not claimed working until reported.

### Task 13: README for the friend

**Files:** Create `README.md`.

- [ ] **Step 1: Write** install (get the SDK zip from viture.com/developer, unzip to `vendor/viture-sdk`, `scripts/bundle.sh --install`), quit SpaceWalker first, grant Screen Recording, shortcut table (Task 11), editing gestures (Task 10), troubleshooting (SDK missing, permission, shortcut conflicts), hardware test checklist (Task 12 Step 5).
- [ ] **Step 2: Verify** every shortcut and path in the README exists in code (`grep`).
- [ ] **Step 3: Commit** `docs: README for installing and using LumaSpace`.
