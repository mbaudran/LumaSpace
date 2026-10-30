# Cinema Ambience — Design

Date: 2026-10-30
Status: approved in chat ("build it")

## Goal

Replace the box-built theater of cinema mode with a Vision Pro-like *ambience*: no room, the
screen floats in darkness and its light spills into the space around it — a soft halo, haze in
the air, a glossy floor that reflects the picture, a few dust motes in the beam — and the Luma's
electrochromic lenses darken the real room while the film plays.

Success: in cinema mode the picture reads as the only light source in a dark, endless space;
the glow follows the picture smoothly (no strobing on cuts); edges don't shimmer in stereo; it
holds 90 Hz at 3840×1200 (target < 4 ms GPU on an M1).

## Constraints

- On the Luma's birdbath optics black is see-through; the lens tint compensates.
- 3DoF, seated. No Xcode: shaders compile at runtime; checks are `LumaChecks`.
- Swift 6.0-compatible. We can't test on glasses; the friend does.
- Environments are a future idea (lake, Moon…); only this ambience ships now, and no picker
  is built until there is a second one.

## The look

- **Screen**: gently curved (radius 1.5 × viewing distance), rounded corners, no frame.
- **Halo**: a curved strip behind the screen, larger than it; each point takes the colour of
  the nearest picture edge (blurred) and fades over ~1–2 m.
- **Haze**: in-scattered light along each view ray from 16 virtual lights spread over the
  screen, in closed form (no ray marching), up to where the ray hits the floor or the screen.
- **Floor**: black lacquer 1.2 m below the eyes. Reflection by mirroring the view ray and
  intersecting the curved screen analytically; blur grows with the distance travelled, Fresnel
  makes it stronger at grazing angles; plus a soft pool of light from the 16 lights. The floor
  itself is black, so it has no visible edge.
- **Dust**: ~400 point sprites drifting slowly in the beam, lit by the haze formula, positions
  a pure function of time.
- **Motion**: the glow texture follows the picture with a 0.3 s exponential smoothing that is
  frame-rate independent; entering fades in from black over 1.2 s (leaving is instant: the
  glasses blink back to 2D anyway).
- **Lens tint**: turned on when cinema starts, restored to what it was when it ends.

## Controls

- Closer/Farther: 7 distance steps, 7–13 m (default 10 m). Bigger/Smaller: screen scale.
- `Command.cycleAmbience` ("Ambience", keywords include "lights"): Off → Soft → Full.
  Off keeps the screen and a faint reflection only.
- IPD unchanged.

## Rendering (per frame, both eyes side by side)

1. **Glow texture**: picture → 256×144 rgba16Float, blended with the previous one (ping-pong)
   for the smoothing, mipmapped. Halo and reflection read it; the 16 light colours are taken
   from it once per frame into a 16×1 texture that the pool, haze and dust read.
2. **Scene pass** into a 4× MSAA rgba16Float target (memoryless on Apple GPUs, resolved):
   floor → halo (additive) → screen (alpha for corners) → dust. The haze is smooth, so it is
   drawn in its own quarter-resolution pass (per eye) and added when compositing.
3. **Bloom**: bright parts → quarter-res, separable Gaussian; blur taps clamp to their eye's
   half so nothing leaks across the stereo seam.
4. **Composite** to the drawable: scene + bloom, soft shoulder tone map that leaves normal
   picture values alone, fade, dither (dark gradients band on 8-bit otherwise).

Ambience Off skips halo, haze, dust and bloom. `LUMA_CINEMA_STATS=1` logs mean GPU time per
second; `LumaSpace --cinema-bench` renders 3840×1200 off screen and prints the time per frame at
each level (M4: 0.7 ms Off, 1.3 ms Full). A shader setup failure logs and refuses cinema mode, as before.

## Code

- `LumaCore/Cinema.swift`: room/seats/surfaces removed. `CinemaSettings` keeps `row`,
  `screenScale`, `ipd`; `lights: RoomLights` becomes `ambience: Ambience` (off/soft/full).
  Decoding still reads the old `lights` key (`dark/dim/lit` → `off/soft/full`).
  `cinemaLayout` returns viewer, screen placement and radius, floor height.
- `LumaCore/CinemaAmbience.swift`: per-level strengths, glow smoothing factor, fade curve,
  screen lights (16), ray → curved screen hit, floor reflection, haze integral, dust motes. The
  shaders mirror these; the checks test the Swift versions.
- `LumaSpace/CinemaRenderer.swift` rewritten around the four steps (same public hooks);
  `CinemaShaders.swift` holds the shaders. `LUMA_CINEMA=test` keeps the colour bars;
  `LUMA_CINEMA=clip` shows moving bars with a flash every 3 s, to judge smoothing and dust.
- `GlassesLink`: `lensTint() -> Bool?` (nil = can't tell) and `setLensTint(_:)`. VITURE maps
  them to `xr_device_provider_get/set_film_mode`, loaded optionally (older SDKs lack them).
  The tint state is logged when cinema starts (`--diagnose` has no live connection to ask).
- README: cinema section, hardware checklist (tint, glow comfort, 90 Hz, reflection depth).

## Testing

LumaChecks: old `lights` files load as `ambience`, round-trip, clamping; distances; ambience
strengths ordered and Off zeroes; smoothing is ~63 % after 0.3 s regardless of frame rate;
fade 0 → 1; lights lie on the screen and face the viewer; ray/screen hits match geometry and
misses report nil; reflections hit the screen from below; haze is 0 at length 0, grows and
saturates; dust stays in its box and is deterministic; simulated tint is set and restored;
"lights" finds Ambience in the palette.
Visual: `LUMA_CINEMA=test|clip` + `LUMA_SNAPSHOT` at each level and head direction, reviewed
by eye; `LUMA_CINEMA_STATS=1` for GPU time.
