# Cinema Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ⌃⌥C turns the Luma into a stereo virtual cinema: a lit theater room whose giant curved screen shows any captured window or display.

**Architecture:** All math (eye offsets, viewports, display-mode choice, theater geometry, settings, command routing) is pure Swift in `LumaCore`, checked by `LumaChecks`. A new `CinemaRenderer` in `LumaSpace` draws the theater twice per frame (left/right half of the drawable) with its own runtime-compiled Metal shader; `Renderer.draw` hands the frame to it while cinema mode is on. `AppController` owns entering/leaving, mirroring game mode.

**Tech Stack:** Swift 6.0, AppKit, Metal/MetalKit (shaders compiled from source at runtime), ScreenCaptureKit via the existing `CaptureService`, VITURE C SDK via `VitureLibrary`.

**Spec:** `docs/superpowers/specs/2026-10-29-cinema-mode-design.md`

## Global Constraints

- Swift 6.0-compatible (friend has Swift 6.1.2): no isolated conformances.
- No Xcode: Metal shaders are source strings compiled with `device.makeLibrary(source:)`; tests are `check(...)` functions in `Sources/LumaChecks`, run with `scripts/checks.sh` (currently 86 checks, all must still pass).
- Build the app with `scripts/bundle.sh`.
- 3D SBS display modes: `0x45` = 3840×1200 @ 90 Hz, `0x42` = 3840×1200 @ 60 Hz. 2D restore goes through the existing `setRate`.
- IPD default 63 mm, range 55–75 mm. Room lights: Dark 0.0, Dim 0.08 (default), Lit 0.2.
- Screen: 8 m wide × scale (0.6–1.6), 10 m from default row, curvature radius 10 m, bottom edge 1.0 m above front floor. 7 rows × 12 seats, 0.55 m seat pitch, 1.0 m row spacing, floor rises 0.15 m per row, default row index 3.
- Hotkey ⌃⌥C. Commit straight to `main`, message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Glasses display blinks during the 3D switch** → LumaSpace must stay on the glasses, not fall back to the preview (Task 6: screen-change grace period; checked by `screenChangeIgnored`).
2. **Cinema source window closed mid-movie** → screen shows "Source unavailable" card, room stays lit by ambient, no crash (Task 5 fallback + Task 6 verification step).
3. **Quitting or unplugging while in cinema** → glasses go back to the 2D rate chosen before (Task 6: `applicationWillTerminate` / `useSimulator` call `exitCinemaMode`; checked through `OutputMode` transitions).
4. **Old `layout.json` without cinema settings** → loads with defaults, nothing moved to `.bad` (Task 4 check).
5. **Odd drawable widths / display stays 1920 wide** → both halves rendered, nothing stretched past the drawable (Task 1 viewport check).

---

### Task 1: Stereo math

**Files:**
- Create: `Sources/LumaCore/Stereo.swift`
- Create: `Sources/LumaChecks/CinemaChecks.swift`
- Modify: `Sources/LumaChecks/main.swift` (call `stereoChecks()` before `finishChecks()`)

**Interfaces:**
- Produces:
  - `public enum Eye: CaseIterable, Sendable { case left, right }`
  - `public enum IPD { public static let range = 0.055...0.075; public static let standard = 0.063 }`
  - `public func eyeOffset(_ eye: Eye, head: Quat, ipd: Double) -> Vec3` — `head.rotate(Vec3(x: ∓ipd/2, y: 0, z: 0))` (left is −x).
  - `public struct EyeViewport: Equatable, Sendable { public var x: Int; public var width: Int; public var height: Int }`
  - `public func eyeViewport(_ eye: Eye, drawableWidth: Int, drawableHeight: Int) -> EyeViewport` — left `x: 0, width: w/2`, right `x: w/2, width: w - w/2`.
  - `public func eyeAspect(drawableWidth: Int, drawableHeight: Int) -> Double` — `Double(w/2) / Double(h)`, 16/10 when h == 0.

- [ ] **Step 1: Write failing checks** in `CinemaChecks.swift` as `func stereoChecks()`:

```swift
check("eyes sit ipd apart on head-local x, symmetric") {
    let l = eyeOffset(.left, head: .identity, ipd: 0.063), r = eyeOffset(.right, head: .identity, ipd: 0.063)
    expectNear(l.x, -0.0315); expectNear(r.x, 0.0315); expectNear(l.y, 0); expectNear(r.z, 0)
}
check("eye offsets turn with the head") {
    let h = Quat(yaw: .pi / 2, pitch: 0, roll: 0)
    let r = eyeOffset(.right, head: h, ipd: 0.06)
    expectNear((r - eyeOffset(.left, head: h, ipd: 0.06)).length, 0.06)
    expectNear(abs(r.z), 0.03, tol: 1e-9); expectNear(r.x, 0, tol: 1e-9)
}
check("viewports split the drawable exactly, odd widths too") {
    for w in [3840, 1920, 1281] {
        let l = eyeViewport(.left, drawableWidth: w, drawableHeight: 1200)
        let r = eyeViewport(.right, drawableWidth: w, drawableHeight: 1200)
        expectEqual(l.x, 0); expectEqual(r.x, l.width); expectEqual(l.width + r.width, w); expectEqual(r.height, 1200)
    }
}
check("each eye's aspect uses half the width") {
    expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 1200), 1.6)
    expectNear(eyeAspect(drawableWidth: 3840, drawableHeight: 0), 1.6)
}
```

- [ ] **Step 2: Run** `scripts/checks.sh` — Expected: `BUILD FAILED` (unknown `eyeOffset`).
- [ ] **Step 3: Implement** `Stereo.swift` with the signatures above.
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `90 passed, 0 failed`.
- [ ] **Step 5: Commit** `git add Sources/LumaCore/Stereo.swift Sources/LumaChecks && git commit -m "Add stereo eye math for cinema mode"`

---

### Task 2: Stereo display modes on the glasses

**Files:**
- Modify: `Sources/LumaCore/Glasses.swift` (protocol + mode helper)
- Modify: `Sources/LumaCore/SimulatedGlasses.swift`
- Modify: `Sources/LumaSpace/VitureGlasses.swift:260-270` (next to `setRate`)
- Test: `Sources/LumaChecks/CinemaChecks.swift` (`func stereoModeChecks()`, registered in `main.swift`)

**Interfaces:**
- Produces:
  - `public func stereoDisplayModes(for rate: DisplayRate) -> [Int32]` — `.hz60 → [0x42]`, `.hz90, .hz120 → [0x45, 0x42]`.
  - `GlassesLink.setStereo(_ on: Bool, rate: DisplayRate) -> Bool` — `on`: try each code from `stereoDisplayModes(for:)` in order, return true at the first SDK success; `off`: `setRate(rate)` and return true.
  - `SimulatedGlasses.stereo: Bool` (`public private(set)`), set by `setStereo`, which always returns true.

- [ ] **Step 1: Write failing checks**

```swift
check("90 and 120 Hz ask for 3D at 90 Hz, then 60 Hz") {
    expectEqual(stereoDisplayModes(for: .hz90), [0x45, 0x42])
    expectEqual(stereoDisplayModes(for: .hz120), [0x45, 0x42])
    expectEqual(stereoDisplayModes(for: .hz60), [0x42])
}
check("simulated glasses accept stereo and drop it again") {
    let g = SimulatedGlasses(reason: "test")
    expect(g.setStereo(true, rate: .hz90)); expect(g.stereo)
    expect(g.setStereo(false, rate: .hz60)); expect(!g.stereo)
}
```

- [ ] **Step 2: Run** `scripts/checks.sh` — Expected: `BUILD FAILED`.
- [ ] **Step 3: Implement** the helper, protocol requirement, simulator, and `VitureGlasses.setStereo` (NSLog each rejected code with its return value, same style as `setRate`).
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `92 passed, 0 failed`; `scripts/bundle.sh` builds.
- [ ] **Step 5: Commit** `"Add 3D side-by-side display modes to glasses link"`

---

### Task 3: Theater geometry and settings

**Files:**
- Create: `Sources/LumaCore/Cinema.swift`
- Test: `Sources/LumaChecks/CinemaChecks.swift` (`func cinemaSceneChecks()`, registered)

**Interfaces:**
- Produces:
  - `public enum RoomLights: String, Codable, CaseIterable, Sendable { case dark, dim, lit }` with `public var ambient: Double` (0, 0.08, 0.2), `public var next: RoomLights` (dark→dim→lit→dark), `public var title: String` ("Dark", "Dim", "Lit").
  - `public struct CinemaSettings: Codable, Equatable, Sendable` — `row: Int = 3` (0...6), `screenScale: Double = 1` (0.6...1.6), `lights: RoomLights = .dim`, `ipd: Double = IPD.standard`; `public static let rows = 0...6`, `public static let scale = 0.6...1.6`; `public var clamped: CinemaSettings` (clamps every field, non-finite → default).
  - `public struct CinemaBox: Equatable, Sendable { public var center: Vec3; public var size: Vec3 }` (axis-aligned).
  - `public struct CinemaSurface: Equatable, Sendable { public var center: Vec3; public var normal: Vec3; public var up: Vec3; public var width: Double; public var height: Double; public var albedo: Vec3 }`
  - `public struct CinemaLayout: Equatable, Sendable` — `viewer: Vec3`, `screenCenter: Vec3`, `screenWidth: Double`, `screenHeight: Double`, `screenRadius: Double`, `room: CinemaBox`, `surfaces: [CinemaSurface]` (floor, ceiling, left, right, back, front wall), `seats: [CinemaBox]`.
  - `public func cinemaLayout(_ s: CinemaSettings, sourceAspect: Double?) -> CinemaLayout`

World frame (metres, −z towards the screen, x right, y up, y = 0 is the front floor):
- Row `r` floor height `0.15 * r`; viewer eye `(0, 0.15r + 1.15, r)`.
- Screen: width `8 * scale`, height `width / aspect` (aspect `sourceAspect` if finite and in `SceneLimits.aspect`, else 16/9), centre `(0, 1.0 + height/2, -7)` so row 3 is 10 m away; `screenRadius = 10`.
- Room box: x half-width `width/2 + 2`, z from `-7.5` to `8.5` (16 m), y from 0 to screen top + 2.
- Seats: rows 0...6, 12 per row, `x = (i - 5.5) * 0.55`, box size `(0.5, 0.9, 0.5)`, centre `(x, 0.15r + 0.45, r + 0.25)`.
- Albedos: walls `(0.45, 0.40, 0.36)`, floor `(0.18, 0.08, 0.08)`, ceiling `(0.20, 0.20, 0.22)`; seats are drawn deep red `(0.45, 0.06, 0.08)` by the renderer.

- [ ] **Step 1: Write failing checks**

```swift
check("default row puts the screen 10 m straight ahead") {
    let l = cinemaLayout(CinemaSettings(), sourceAspect: 16.0 / 9)
    expectNear(l.viewer.z - l.screenCenter.z, 10); expectNear(l.screenCenter.x, 0); expectNear(l.screenWidth, 8)
}
check("closer rows are nearer the screen") {
    var s = CinemaSettings(); s.row = 0
    let front = cinemaLayout(s, sourceAspect: nil); s.row = 6
    expect(cinemaLayout(s, sourceAspect: nil).viewer.z - front.viewer.z > 5)
}
check("screen, viewer and every seat are inside the room; seats stay below the eyes") {
    let l = cinemaLayout(CinemaSettings(), sourceAspect: 2.39)
    func inside(_ p: Vec3) -> Bool { abs(p.x - l.room.center.x) <= l.room.size.x / 2 && abs(p.y - l.room.center.y) <= l.room.size.y / 2 && abs(p.z - l.room.center.z) <= l.room.size.z / 2 }
    expect(inside(l.screenCenter)); expect(inside(l.viewer)); expectEqual(l.seats.count, 84)
    // A seat's top stays below the eye height of someone sitting in that row.
    expect(l.seats.allSatisfy { inside($0.center) && $0.center.y + $0.size.y / 2 < 0.15 * ($0.center.z - 0.25) + 1.15 })
}
check("settings clamp and lights cycle") {
    let c = CinemaSettings(row: 12, screenScale: .nan, lights: .lit, ipd: 0.2).clamped
    expectEqual(c.row, 6); expectNear(c.screenScale, 1); expectNear(c.ipd, 0.075)
    expectEqual(RoomLights.lit.next, .dark); expectNear(RoomLights.dim.ambient, 0.08)
}
check("a missing or silly source aspect falls back to 16:9") {
    expectNear(cinemaLayout(CinemaSettings(), sourceAspect: nil).screenHeight, 4.5)
    expectNear(cinemaLayout(CinemaSettings(), sourceAspect: 0).screenHeight, 4.5)
}
```

(Give `CinemaSettings` a memberwise `public init(row:screenScale:lights:ipd:)` with the defaults above.)

- [ ] **Step 2: Run** `scripts/checks.sh` — Expected: `BUILD FAILED`.
- [ ] **Step 3: Implement** `Cinema.swift`.
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `97 passed, 0 failed`.
- [ ] **Step 5: Commit** `"Add cinema theater geometry and settings"`

---

### Task 4: Commands, mode switching and persistence

**Files:**
- Modify: `Sources/LumaCore/Commands.swift` (new cases, titles, keywords, `all`)
- Modify: `Sources/LumaCore/Cinema.swift` (routing + output mode)
- Modify: `Sources/LumaCore/LayoutStore.swift` (`cinema` field, clamp on load)
- Test: `Sources/LumaChecks/CinemaChecks.swift` (`func cinemaCommandChecks()`, registered)

**Interfaces:**
- Consumes: `CinemaSettings` (Task 3).
- Produces:
  - `Command.toggleCinemaMode` — title "Cinema Mode", keywords `["vr", "movie", "theater", "3d", "film"]`.
  - `Command.nudgeIPD(Double)` — argument in metres (±0.001); titles "IPD +" / "IPD −", keywords `["eyes", "depth", "stereo"]`.
  - `Command.cycleRoomLights` — title "Room Lights", keywords `["cinema", "ambient", "dark"]`.
  - `Command.all` gains `.toggleCinemaMode, .cycleRoomLights, .nudgeIPD(0.001), .nudgeIPD(-0.001)` right after `.toggleGameMode`.
  - `public func cinemaAdjusted(_ s: CinemaSettings, by c: Command) -> CinemaSettings?` — `.nudgeDistance(d)`: row −1 if d < 0 else +1; `.resizeSelected(f)`: scale × f; `.nudgeIPD(d)`: ipd + d; `.cycleRoomLights`: lights.next; any other command → nil. Result is `.clamped`.
  - `public enum OutputMode: Equatable, Sendable { case panels, game, cinema }` and `public func outputMode(after current: OutputMode, toggling m: OutputMode) -> OutputMode` — same mode → `.panels`, otherwise `m`.
  - `LayoutFile.cinema: CinemaSettings?` (optional so old files decode; `init` gets `cinema: CinemaSettings? = nil`); `LayoutStore.load` replaces it with `.clamped`.

- [ ] **Step 1: Write failing checks**

```swift
check("cinema mode is in the palette as 'cinema', 'movie' and 'vr'") {
    expectEqual(paletteMatches("cinema", in: Command.all).first, .toggleCinemaMode)
    expect(paletteMatches("movie", in: Command.all).contains(.toggleCinemaMode))
    expect(paletteMatches("vr", in: Command.all).contains(.toggleCinemaMode))
}
check("closer/farther pick rows, bigger/smaller scale the screen") {
    let s = CinemaSettings()
    expectEqual(cinemaAdjusted(s, by: .nudgeDistance(-0.25))?.row, 2)
    expectEqual(cinemaAdjusted(s, by: .nudgeDistance(0.25))?.row, 4)
    expectNear(cinemaAdjusted(s, by: .resizeSelected(1.1))!.screenScale, 1.1)
    expectNear(cinemaAdjusted(s, by: .nudgeIPD(0.001))!.ipd, 0.064)
    expectEqual(cinemaAdjusted(s, by: .cycleRoomLights)?.lights, .lit)
    expectEqual(cinemaAdjusted(s, by: .recenter), nil)
}
check("cinema and game mode exclude each other; toggling again returns to panels") {
    expectEqual(outputMode(after: .panels, toggling: .cinema), .cinema)
    expectEqual(outputMode(after: .cinema, toggling: .cinema), .panels)
    expectEqual(outputMode(after: .game, toggling: .cinema), .cinema)
    expectEqual(outputMode(after: .cinema, toggling: .game), .game)
}
check("a layout file without cinema settings still loads") {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("luma-cinema-\(UUID()).json")
    try #"{"version":1,"panels":[],"distance":2,"smoothFollow":false,"lockedAxes":[]}"#.write(to: url, atomically: true, encoding: .utf8)
    let f = LayoutStore(url: url).load()
    expectEqual(f.cinema, nil); expectNear(f.distance, 2)
    expect(!FileManager.default.fileExists(atPath: url.path + ".bad"))
}
check("cinema settings round-trip and are clamped on load") {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("luma-cinema-\(UUID()).json")
    let store = LayoutStore(url: url)
    try store.save(LayoutFile(panels: [], distance: 2, smoothFollow: false, lockedAxes: [],
                              cinema: CinemaSettings(row: 9, screenScale: 1.2, lights: .lit, ipd: 0.06)))
    let c = store.load().cinema
    expectEqual(c?.row, 6); expectEqual(c?.lights, .lit); expectNear(c?.ipd ?? 0, 0.06)
}
```

- [ ] **Step 2: Run** `scripts/checks.sh` — Expected: `BUILD FAILED`.
- [ ] **Step 3: Implement.** Exhaustive `switch`es in `Commands.swift` (title/keywords) and the `perform` switch in `AppController.swift` will fail to compile — add temporary `case .toggleCinemaMode, .nudgeIPD, .cycleRoomLights: break` in `AppController.perform` so the app still builds (Task 6 replaces it).
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `102 passed, 0 failed`; `scripts/bundle.sh` builds.
- [ ] **Step 5: Commit** `"Add cinema commands, mode switching and saved settings"`

---

### Task 5: Cinema renderer

**Files:**
- Create: `Sources/LumaSpace/CinemaRenderer.swift`
- Create: `Sources/LumaSpace/CinemaShaders.swift` (`let cinemaShaderSource = """ … """`)
- Modify: `Sources/LumaSpace/Renderer.swift` (make `perspective`/`translation` internal instead of `private`; add `var cinema: CinemaRenderer?`; in `draw(in:)`, when `cinema` is set, call it instead of drawing panels, keeping `onFrame`/present/commit)
- Modify: `Sources/LumaSpace/AppController.swift` only for the debug hook below

**Interfaces:**
- Consumes: `cinemaLayout`, `CinemaSettings`, `eyeOffset`, `eyeViewport`, `eyeAspect`, `verticalFOV(aspect:)`.
- Produces (used by Task 6):
  - `@MainActor final class CinemaRenderer { init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) }`
  - `var settings: CinemaSettings` (recompute layout when it or the source aspect changes)
  - `var screenTexture: () -> MTLTexture?` and `var fallbackTexture: () -> MTLTexture?` (the "Source unavailable" card)
  - `func encode(into pass: MTLRenderPassDescriptor, drawableSize: CGSize, head: Quat, commandBuffer: MTLCommandBuffer)`
  - `static func testPattern(device: MTLDevice) -> MTLTexture?` — 1920×1080 SMPTE-style colour bars, used by `LUMA_CINEMA=test`.

Rendering decisions:
- The view's `depthStencilPixelFormat` is set to `.depth32Float` by the renderer when cinema starts (and `.invalid` again when it ends) so `currentRenderPassDescriptor` carries a depth attachment; pipelines use `depthAttachmentPixelFormat = .depth32Float`, depth test `.less`, write on.
- Per eye: `setViewport` + `setScissorRect` from `eyeViewport`; view = `translation(-(layout.viewer + eyeOffset(eye, head:, ipd:))) ` composed with `head.conjugate.matrix` (rotate after translate: `rot * trans`); projection `perspective(fovY: verticalFOV(aspect: eyeAspect(...)), aspect:, near: 0.05, far: 50)`.
- Geometry from `vertex_id`, no vertex buffers: screen = 64-segment cylinder strip (130 vertices) bending around the viewer's row-3 position with `screenRadius`; surfaces = one 4-vertex strip each; seats = 36-vertex box, `instance_id` indexes a `[float4x4]` buffer built once per layout change.
- Screen light: each frame blit `screenTexture()` (or fallback) into a private 64×32 `rgba8Unorm` texture with 7 mip levels (`MTLBlitCommandEncoder.copy` can't scale, so do it with a tiny full-screen-quad render pass sampling linear, then `generateMipmaps`). Room fragment shading:

```
light = ambient * albedo
for i in 0..<8:                       // 8 samples across the screen width at mid height
    s   = screen point i (world)      // passed as uniform array
    c   = lightTex.sample(mip 3, u = (i + 0.5) / 8, v = 0.5)
    L   = s - worldPos;  d = length(L)
    light += albedo * c.rgb * max(dot(n, L / d), 0) * 6.0 / (1 + d * d * 0.08) / 8
color = light
```

 The screen itself renders the full-resolution texture unlit. Gains (6.0, 0.08) are starting values: tune with the snapshot so the front walls clearly pick up the bars' colours and the back of the room stays dim.

- Debug hook: in `AppController.applicationDidFinishLaunching`, after `Snapshot.installIfRequested`, if `LUMA_CINEMA=test`, create a `CinemaRenderer` whose `screenTexture` returns `CinemaRenderer.testPattern`, assign it to `renderer.cinema`, and set the preview `contentAspectRatio` to 32:10. (Task 6 turns this into the real `enterCinemaMode` path.)

- [ ] **Step 1: Build** `scripts/bundle.sh` — Expected: builds (checks unchanged).
- [ ] **Step 2: Snapshot** `LUMA_CINEMA=test LUMA_SNAPSHOT=$TMPDIR/cinema.png build/LumaSpace.app/Contents/MacOS/LumaSpace` then open the PNG with the Read tool. Expected: two side-by-side views of the same theater (slight horizontal shift between them), colour bars on a curved screen, seat rows in the lower part of the frame, walls tinted by the bars. Adjust gains until that holds.
- [ ] **Step 3: Snapshot looking left** with `LUMA_SIM_YAW=40` added. Expected: side wall and seats visible, screen off to the right edge; nothing stretched or missing in either half.
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `102 passed, 0 failed`.
- [ ] **Step 5: Commit** `"Add stereo cinema renderer"`

---

### Task 6: Cinema mode in the app

**Files:**
- Modify: `Sources/LumaSpace/AppController.swift`
- Modify: `Sources/LumaSpace/Hotkeys.swift` (⌃⌥C)
- Modify: `Sources/LumaSpace/MenuBarController.swift` (menu items)
- Modify: `Sources/LumaSpace/main.swift` (`--diagnose` pixel size)
- Modify: `Sources/LumaCore/Cinema.swift` + checks (`screenChangeIgnored`)

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `public func screenChangeIgnored(now: Double, until: Double?) -> Bool` (LumaCore) — true while `now < until`.
  - `AppController`: `private(set) var mode: OutputMode` (replaces the `gameMode` Bool; keep `var gameMode: Bool { mode == .game }` for the menu), `var cinema = CinemaSettings()`, `private var cinemaSource: PanelSource?`, `private let cinemaPanelID = UUID()`, `private var rateBeforeCinema: DisplayRate?`, `private var ignoreScreenChangesUntil: Double?`, `func enterCinemaMode()`, `func exitCinemaMode()`.

Behaviour:
- `perform`: `.toggleGameMode` / `.toggleCinemaMode` compute `outputMode(after: mode, toggling:)`, exit the current mode, then enter the new one. When `mode == .cinema`, first try `cinemaAdjusted(cinema, by: c)`; if it returns settings, store them, push to `renderer.cinema?.settings`, `markDirty()`, and skip the panel handling. `.nudgeIPD` and `.cycleRoomLights` update `cinema` in any mode.
- `enterCinemaMode()`: source = selected panel's source if it has a `key`, else `picker.present(...)`; a cancelled picker leaves `mode` unchanged. Then `mode = .cinema`, `rateBeforeCinema = rate ?? .hz60`, `ignoreScreenChangesUntil = now + 3`, `glasses.setStereo(true, rate: .hz90)` (NSLog when it returns false and continue), create the `CinemaRenderer` (screen texture = `capture.texture(for:)` of the source; fallback = the renderer's "Source unavailable" card — expose `Renderer.unavailableCard(for: PanelSource) -> MTLTexture?` wrapping the existing private `label(for:)`), `renderer.cinema = it`, preview `contentAspectRatio` 32:10, `capture.sync(panels: capturedPanels)`. After 2 s NSLog the glasses display's `CGDisplayPixelsWide`×`High`.
- `capturedPanels`: `.game → []`, `.cinema → [Panel(id: cinemaPanelID, source: cinemaSource, …)]` (only the source matters), `.panels → scene.panels`.
- `exitCinemaMode()`: guard `mode == .cinema`; `mode = .panels`; `renderer.cinema = nil`; `ignoreScreenChangesUntil = now + 3`; `glasses.setStereo(false, rate: rateBeforeCinema ?? .hz60)`; preview aspect back to 16:9; `Task { await refreshSources() }`.
- Called from: `applicationWillTerminate`, `useSimulator` (both already call `exitGameMode`), and `enterGameMode` via the mode switch.
- `screensChanged`: return early when `mode == .game` or `screenChangeIgnored(now:until:)`; afterwards the existing frame-update branch resizes the glasses window to the 3840-wide display.
- `updateGrab`: return immediately in cinema (no grabbing, no reticle).
- `loadLayout`/`saveIfDirty`: read/write `LayoutFile.cinema`.
- Hotkey: `HotkeySpec(keyCode: kVK_ANSI_C, shift: false, label: "⌃⌥C", action: .command(.toggleCinemaMode))`.
- Menu: after Game Mode add `command(.toggleCinemaMode, checked: app.mode == .cinema)` and a "Cinema" submenu with `cycleRoomLights` (title `"Room Lights: \(app.cinema.lights.title)"`), `nudgeIPD(0.001)`, `nudgeIPD(-0.001)`.
- `--diagnose`: the glasses line also prints `CGDisplayPixelsWide/High` of the VITURE display.
- `LUMA_CINEMA=test` (from Task 5) now calls `enterCinemaMode` with the test pattern as the screen texture instead of the ad-hoc setup.

- [ ] **Step 1: Write failing check**

```swift
check("screen changes are ignored for a grace period after a mode switch") {
    expect(screenChangeIgnored(now: 1, until: 3)); expect(!screenChangeIgnored(now: 3.5, until: 3))
    expect(!screenChangeIgnored(now: 1, until: nil))
}
```

- [ ] **Step 2: Run** `scripts/checks.sh` — Expected: `BUILD FAILED`.
- [ ] **Step 3: Implement** the helper and all behaviour above.
- [ ] **Step 4: Run** `scripts/checks.sh` — Expected: `103 passed, 0 failed`; `scripts/bundle.sh` builds without warnings about isolated conformances.
- [ ] **Step 5: Snapshot** `LUMA_CINEMA=test LUMA_SNAPSHOT=$TMPDIR/cinema-app.png …` — Expected: same theater as Task 5, now through `enterCinemaMode`.
- [ ] **Step 6: Manual run in the simulator** (screen recording permission granted): launch the app, open a video in any player, press ⌃⌥C, pick the player window → theater with the video in the preview; ⌃⌥= / ⌃⌥- change rows; ⌃⌥] / ⌃⌥[ resize; close the player window → "Source unavailable" card, app keeps running; ⌃⌥C → panels back. Record what was and wasn't checked in the commit message.
- [ ] **Step 7: Commit** `"Add cinema mode: stereo theater for any window or display"`

---

### Task 7: Docs

**Files:**
- Modify: `README.md` (Highlights line, shortcut table/list if present, "Hardware test checklist")

- [ ] **Step 1: Add** a Highlights bullet: "🎬 **Cinema mode.** ⌃⌥C puts any window or display on a giant screen in a 3D theater lit by the movie." Add ⌃⌥C wherever shortcuts are listed.
- [ ] **Step 2: Add** a "Cinema mode" block to the hardware checklist:
  - ⌃⌥C switches the glasses into 3D (picture becomes a 3D theater, not two squeezed copies). If it shows two squeezed copies, run `LumaSpace --diagnose` while in cinema mode and send the "glasses display" line.
  - Depth looks natural; try IPD +/− in the palette if the screen looks doubled.
  - Room brightness with Dark / Dim / Lit.
  - Screen size and rows feel right.
  - ⌃⌥C again returns to the panels at the previous refresh rate; unplugging in cinema mode doesn't leave the glasses in 3D.
- [ ] **Step 3: Run** `scripts/checks.sh` — Expected: `103 passed, 0 failed`.
- [ ] **Step 4: Commit** `"Document cinema mode"`
