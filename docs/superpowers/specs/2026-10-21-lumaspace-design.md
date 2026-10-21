# LumaSpace — design

A native macOS app that replaces SpaceWalker for the VITURE Luma glasses, with
free-form window layout and fast quick controls.

## Goal and context

- Friend owns VITURE Luma glasses (Gen1, **3DoF only**, no camera) and finds
  SpaceWalker's UI poor. Mac, Apple silicon, macOS 26.
- Build a better replacement on the **official VITURE Glasses SDK** (C API).
  We do not reverse engineer SpaceWalker; its public docs are used only as a UX
  reference.
- Priorities, in order: (1) free window/screen layout, (2) quick controls.
  Head-tracking feel and visual polish come later.
- The author has no glasses on hand, so stages 1–3 must be fully testable with a
  simulated head pose.

## Non-goals (v1)

- 6DoF / Luma Ultra, pass-through camera, Windows/Linux/Android/iOS.
- Reproducing any SpaceWalker code or assets.
- Windows-on-glasses 3D/SBS content playback.

## Constraints

- Toolchain: Command Line Tools only (no Xcode). Build with SwiftPM. Metal
  shaders are compiled at runtime from source strings
  (`MTLDevice.makeLibrary(source:)`) because the offline `metal` compiler ships
  with Xcode.
- The SDK ships as `libglasses.dylib` (arm64 macOS). The public docs give no
  download link; it must be obtained from VITURE's developer portal. Until then
  `GlassesLink` runs on a simulator implementation.
- Only one process may own the glasses' IMU, so SpaceWalker must be closed while
  LumaSpace runs.

## Architecture

Units communicate through small protocols and can be tested independently.

| Unit | Responsibility | Depends on |
|---|---|---|
| `GlassesLink` | Protocol: head pose stream (quaternion), brightness, volume, display mode, recenter, connection state. Implementations: `SimulatedGlasses` (mouse/keyboard driven), `VitureGlasses` (SDK via C interop). | SDK (real impl only) |
| `CaptureService` | ScreenCaptureKit streams of windows/displays, delivered as Metal textures. Permission handling. | ScreenCaptureKit |
| `SpatialScene` | Pure layout model: panels with position, size, anchor; snapping, grouping, presets, serialization. No rendering. | nothing |
| `Renderer` | Metal. Draws panels with the inverse head pose into the output window on the glasses display (or a preview window in simulator mode). | `SpatialScene`, `CaptureService`, `GlassesLink` pose |
| `Controls` | Menu bar item and a floating radial/command-palette overlay. Issues commands to `GlassesLink` and `SpatialScene`. | `GlassesLink`, `SpatialScene` |

SwiftPM layout: library targets per unit plus an executable `LumaSpaceApp`.
`SpatialScene` and the `GlassesLink` protocol have no platform dependencies so
tests run with `swift test`.

## Data flow

`GlassesLink` pose → `Renderer` (view matrix) · `CaptureService` frames →
`Renderer` (panel textures) · `Controls` / input → `SpatialScene` mutations →
`Renderer` (next frame). Layout state persists to JSON in Application Support.

## Stages

1. **Simulator + one screen.** Package skeleton, `SimulatedGlasses`, `Renderer`
   showing one captured display as a head-tracked panel in a preview window.
2. **Free layout.** Multiple panels from windows/displays; move, resize, snap,
   group; presets (single, dual, triple, ultrawide, coding); save/restore.
3. **Quick controls.** Menu bar item; radial/command-palette overlay for
   brightness, volume, distance, recenter, layout presets; global shortcuts.
4. **Real glasses.** `VitureGlasses` over the SDK; output to the glasses
   display; recenter, drift handling, Smooth Follow; themes/shortcut parity.
   Blocked until the SDK library and a pair of glasses are available.

## Error handling

- Screen Recording permission missing: show a one-screen explainer with a button
  that opens System Settings.
- Glasses disconnected: fall back to the preview window, keep layout state,
  reconnect automatically.
- SDK library missing: app runs in simulator mode and says so in the menu bar.

## Testing

- Unit tests (`swift test`) for `SpatialScene` (snapping, grouping, presets,
  serialization) and for pose math.
- Simulator-driven manual checks for rendering and controls.
- Stage 4 is verified on real hardware by the friend; no claims of working
  head tracking before that.

## Risks

- SDK download availability (blocks stage 4 only).
- Runtime-compiled shaders add a small startup cost; acceptable.
- Screen capture latency affects perceived quality; measure in stage 1.
