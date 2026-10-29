# Cinema Mode — Design

Date: 2026-10-29
Status: approved in chat, awaiting spec review

## Goal

Use the VITURE Luma as a seated, 3DoF "VR" viewer, starting with a **virtual cinema**: a lit
theater room rendered in true stereo, with a giant screen showing any captured window or
display. The user plays a movie in any app (browser, VLC, IINA, Netflix…) and watches it in the
theater.

Success: on the friend's glasses, ⌃⌥C switches into a stereo theater whose screen shows the
chosen source, the room stays fixed when turning the head, the walls pick up the movie's
colours, and ⌃⌥C again returns to the normal panels at the previous refresh rate.

## Constraints

- 3DoF only (rotation). No positional tracking, no controllers.
- On the Luma's birdbath optics black is see-through; only lit surfaces are visible.
- No Xcode: shaders are compiled at runtime from source (as `Shaders.swift` does today);
  tests are `LumaChecks` run by `scripts/checks.sh`.
- Swift 6.0-compatible code (friend's Mac has Swift 6.1.2).
- Nothing can be verified on real glasses by us; the friend tests.

## Decisions

| Topic | Decision |
|---|---|
| Content | Existing `CaptureService` stream of one window or display. No built-in player in v1. |
| Environment | Lit theater room, built in code (approach A). No external 3D assets. |
| Rendering | Our own Metal renderer, stereo by drawing each eye into half the drawable. |

## 1. Entering and leaving

- New `Command.toggleCinemaMode`, title "Cinema Mode", keywords
  `["vr", "movie", "theater", "3d", "film"]`, hotkey **⌃⌥C**, in palette and menu bar.
- **Enter**
  1. Pick the source: the selected panel's source if any, otherwise open the source picker.
     Cancelling the picker aborts entering.
  2. If game mode is on, exit it first (the modes are mutually exclusive).
  3. Remember the current `DisplayRate`, then ask the glasses for 3D SBS: `0x45`
     (3840×1200 @ 90 Hz); if the SDK returns an error, try `0x42` (3840×1200 @ 60 Hz). If both
     fail, stay in 2D and render stereo anyway (the user sees a squeezed side-by-side image),
     and log the failure.
  4. Hide normal panels from rendering; capture only the cinema source; render the theater.
- **Exit** (⌃⌥C, quit, glasses unplugged, switching to simulator, entering game mode):
  restore the remembered 2D rate via `setRate`, restore panel rendering and captures.
- The decision of which display mode to try next lives in LumaCore as a pure function so it
  can be checked.

### GlassesLink changes

Add `func setStereo(_ on: Bool, rate: DisplayRate) -> Bool` to `GlassesLink`:
- `VitureGlasses`: maps to the SDK modes above (90 Hz → `0x45`, falling back to `0x42`;
  60 Hz → `0x42`), returns whether a 3D mode was accepted. `on == false` calls `setRate(rate)`.
- `SimulatedGlasses`: records the call and returns `true`.

## 2. Stereo rendering

- `Renderer` gains a `stereo: StereoConfig?` (nil = today's mono path, unchanged).
- When set, each frame encodes two passes into the same drawable using viewports
  (`MTLViewport`) and scissor rects for the left and right halves.
- Per-eye view matrix: `eyeTranslation(±ipd/2 along head-local x) * head.conjugate`.
  Eye positions are computed in LumaCore (`StereoMath`) so they are testable without Metal.
- Per-eye projection: existing `verticalFOV(aspect:)` with the aspect of **one half**
  (1920×1200 → 1.6).
- IPD: default 63 mm, range 55–75 mm, commands `Command.nudgeIPD(±1)` (titles "IPD +"/"IPD −"),
  persisted with the layout (`LayoutStore`, optional field with default so old files load).
- The renderer always splits whatever drawable size it receives. `--diagnose` gains a line
  printing the glasses display's pixel size and mode after a stereo request, to answer the
  open hardware question (does macOS see a 3840-wide display?).
- The simulator preview window shows the SBS frame too (aspect set to 32:10 while in cinema).

## 3. The theater

### Geometry — `CinemaScene` (LumaCore)

Pure value type producing the room description; no Metal types.

- Coordinates: metres, viewer origin at eye height, −z forward (matching `SpatialScene`).
- **Screen**: cylindrical section, default width 8 m, aspect from the source (fallback 16:9),
  centre 10 m in front of the default seat, bottom edge 1.0 m above floor level of the front.
  Curvature radius = screen distance. Size multiplier range 0.6–1.6.
- **Room**: box around the screen and seating: width screen width + 4 m, depth 16 m, height
  screen top + 2 m. Floor slopes up 0.15 m per seat row toward the back.
- **Seats**: 7 rows × 12 seats, 0.55 m pitch, 1.0 m row spacing, each a rounded box
  (seat + back) emitted as instance transforms. The viewer sits in a row index (default 3,
  range 0–6); "Closer/Farther" changes the row, which moves the viewer origin.
- Output: `screen` (transform, size, curvature), `surfaces` (wall/floor/ceiling quads with
  normals and base albedo), `seatInstances` ([transform]). Recomputed only when row, size or
  source aspect change.

### Rendering — `CinemaRenderer` (LumaSpace) + `cinemaShaderSource`

- Separate pipeline from panels; same runtime-compiled approach.
- Screen: tessellated cylinder strip sampling the capture texture.
- **Screen light**: each frame, blit the capture texture into a 64×32 texture with mipmaps,
  `generateMipmaps`, and sample a low mip (≈8×4) as an area light. Room fragments get light
  from the screen by sampling the low mip at the projected horizontal position, attenuated
  by distance and the surface normal's angle to the screen. Seats use the same shader.
- **Ambient** from the room-lights setting: Dark 0.0, Dim 0.08, Lit 0.2 (default Dim). Walls
  are mid-grey-warm albedo, seats deep red, floor dark carpet; values tuned via snapshot.
- Depth buffer enabled for the cinema pipeline (`depth32Float`).
- When the source is unavailable, the screen shows the existing "Source unavailable" label
  texture and the room uses ambient only.

## 4. Controls in cinema mode

| Action | Effect |
|---|---|
| Recenter | Screen straight ahead (existing recenter). |
| Closer / Farther (existing commands) | Change seat row. |
| Bigger / Smaller (existing commands) | Screen size multiplier. |
| `Command.cycleRoomLights` "Room Lights" | Dark → Dim → Lit. |
| IPD + / IPD − | Adjust IPD ±1 mm. |

Existing commands are routed to the cinema when it is active. Keyboard focus and audio remain
with the playing app; LumaSpace's grab/drag panel interactions are disabled in cinema.

## 5. Testing

- `Sources/LumaChecks/CinemaChecks.swift`:
  - Eye positions: left/right differ only by IPD along head-local x, symmetric about centre,
    rotate with head.
  - Viewport split for odd and even widths covers the drawable exactly.
  - Per-eye aspect uses half width.
  - `CinemaScene`: screen centred ahead, inside the room; all seats inside the room and below
    eye height; row changes move the viewer toward/away from the screen; size clamps.
  - Display-mode selection: 90 → `0x45` then `0x42`; 60 → `0x42`; restore returns prior rate.
  - Mode state: entering cinema exits game mode and vice versa; exit restores rate and panels;
    IPD clamps and persists with old layout files still loading.
- Visual: `LUMA_DEMO` + `LUMA_SNAPSHOT` with a new `LUMA_CINEMA=1` renders an SBS frame with a
  test-pattern screen; inspect the PNG.
- Hardware: add a "Cinema mode" block to the README hardware checklist (3D mode switches,
  depth comfortable, room brightness, screen size, exit restores 2D).

## Out of scope (v1)

Built-in video player, stereo (SBS) movie content on the screen, other environments,
gamepad input, positional tracking.

## Risks

- **macOS may not expose a 3840-wide display after the SBS switch.** Mitigated by always
  splitting whatever drawable we get and logging the size via `--diagnose`.
- **The SDK may reject 3D modes on Luma** (constants may target other models). Mitigated by the
  0x45 → 0x42 fallback and logged return codes; native `VITURE_NATIVE_DISPLAY_MODE_3D_SBS_*`
  codes are a follow-up if needed.
- **Capture frame rate below display rate** is fine: the room re-renders with head motion at
  display rate and reuses the last capture texture.
