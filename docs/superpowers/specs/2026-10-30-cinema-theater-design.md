# Cinema Theater — Design

Date: 2026-10-30
Status: approved in chat ("build it"); builds on 2026-10-30-cinema-ambience-design.md

## Goal

A second cinema environment next to the void: a realistic premium movie theater (Dolby Cinema
style) that keeps the ambience technology — the film lights the room, haze, dust, bloom.

## Decisions

| Topic | Decision |
|---|---|
| Style | Modern premium: black leather recliners, charcoal acoustic fabric, warm LED strips, step lights, dark carpet |
| Assets | Geometry generated in code (LumaCore/Theater.swift); CC0 ambientCG textures (Leather026, Fabric031, Fabric023) at 1K in Resources/Theater, ~2 MB. Paid models can't ship in an MIT repo; a 360° photo has no depth and can't be lit by the film. |
| Environments | `CinemaEnvironment` (void, theater) in `CinemaSettings`, default theater; `Command.cycleEnvironment` ("Environment"). Old layouts open in the theater. |
| Rows | 8 stadium rows (0.4 m rise, 1.1 m apart), 9 seats; you sit in the middle seat of the chosen row. Default row 5 for both environments (void: 5–12 m, row 5 = 10 m as before). |
| Screen | 7.5 m wide at scale 1 (fits the Luma's ~45° view from the middle rows), bottom 0.9 m, slight curve (30 m radius). |

## Rendering

- Whole pipeline in linear light; the composite encodes for the display (void gains retuned).
- Theater surfaces: albedo/normal/roughness texture arrays, normal mapping from screen-space
  derivatives, 8 screen area lights (diffuse + Blinn-Phong), bounce fill in the film's average
  colour, house lights (fill, overhead sheen, LED wall wash), emissive LED strips, step lights
  and projector port, baked seat AO plus analytic AO under the rows and at riser corners.
- Soft seat shadows from a 2048² shadow map seen from behind the screen, drawn once.
- Haze ray length uses the hall box and a sloped floor plane; Full ambience adds a projector
  beam marched through the haze carrying the picture.
- Theater ambience: Off (screen light only), Soft (house 0.25, light haze, faint beam),
  Full (house lights up, more haze, full beam). House lights stay up 3 s after entering, then ease.
- Budget: `--cinema-bench` on M4 at 3840×1200: 2.5 ms Off, 3.1 ms Soft/Full.

## Testing

LumaChecks: environment default/decoding/cycling; middle seat per row; every row sees the
whole screen over the seats in front; screen fits the hall at any size and aspect; haze floor
plane under the seats; projector in the hall; mesh normals and AO sane; seats and armrests
don't overlap; house-light schedule and theater ambience levels. Visual: snapshots per row,
direction and ambience (`LUMA_ENVIRONMENT`, `LUMA_ROW`, `LUMA_AMBIENCE`).
