# LumaSpace

A menu-bar Mac app that puts your windows and displays on **VITURE Luma** glasses as
virtual screens fixed in space — with free placement, snapping, layout presets and a
command palette. Built on the official VITURE Glasses SDK; it does not use SpaceWalker.

Apple silicon, macOS 14 or later. Luma tracking is 3DoF (screens stay put when you turn
your head; they don't move when you lean).

## Install

1. Download **VITURE XR Glasses SDK for macOS** from <https://www.viture.com/developer>.
   Leave the zip in `~/Downloads` (or this folder) — the build script finds and unpacks it.
   (The SDK isn't redistributed in this repo.)
2. Build and install — only Apple's Command Line Tools are needed, not Xcode:
   ```sh
   scripts/bundle.sh --install
   ```
   It needs Swift 6.0 or later (`swift --version`; update with `xcode-select --install` or
   Software Update) and stops with an error if it can't find the SDK. To update LumaSpace
   later, `git pull` (or download the ZIP again) and rerun this step. Then check it's all in place:
   ```sh
   /Applications/LumaSpace.app/Contents/MacOS/LumaSpace --diagnose
   ```
   With the glasses plugged in you want `sdk: loaded`, one USB device "accepted by SDK",
   and a `glasses display`.
3. **Quit SpaceWalker.** Only one app can read the glasses' head tracking at a time.
4. Open `/Applications/LumaSpace.app`. The first time, macOS asks for **Screen Recording**
   permission (System Settings → Privacy & Security → Screen Recording). Allow it and reopen.
5. Plug in the glasses. LumaSpace finds them within a couple of seconds, goes fullscreen
   on the VITURE display and recenters.

Without glasses (or without the SDK) LumaSpace runs a **simulator** in a preview window —
handy for setting up layouts at your desk.

## Using it

Everything lives under the 👓 icon in the menu bar, and in the **command palette**
(**⌃⌥Space**): type a few letters ("tri", "rec", "bri+") and press ↩.

### Shortcuts (work from any app)

| Shortcut | Action |
|---|---|
| ⌃⌥Space | Command palette |
| ⌃⌥R | Recenter |
| ⌃⌥1 … ⌃⌥6 | Layout: Single, Dual, Triple, Stacked, Ultrawide, Coding |
| ⌃⌥= / ⌃⌥- | Screens closer / farther |
| ⌃⌥] / ⌃⌥[ | Selected screen bigger / smaller |
| ⌃⌥A | Add a window or display |
| ⌃⌥N | New virtual screen |
| ⌃⌥G | Game mode on/off |
| ⌃⌥F | Smooth Follow on/off |
| ⌃⌥B / ⌃⌥⇧B | Brightness up / down |

If another app already owns one of these, the menu shows "Shortcut … unavailable".

### Arranging screens in the glasses

- **Hold ⌃⌥** and look at a screen: a blue ring marks the centre of your view and that
  screen is grabbed. Move the mouse to move it; let go to drop it.
- Screens **snap** edge-to-edge with their neighbours and to a 5° grid (toggle with
  "Snapping" in the menu or palette).
- Presets group their screens, so moving one moves the whole layout. Use
  "Ungroup Selected" to move one on its own, "Group All Screens" to join them again.
- **⌃⌥A** opens a searchable list of windows and displays; the new screen appears where
  you're looking.

### Virtual screens (extra monitors)

A panel can show the Mac's screen, one app window, or a **virtual screen** — an extra
monitor that LumaSpace creates. macOS treats it like a plugged-in display: drag windows
onto it and move the mouse across.

- **⌃⌥N** (or "New Virtual Screen") adds one where you're looking; up to 4.
- **Dual** and **Triple** fill their empty slots with virtual screens — Triple puts the Mac
  screen in the middle with a virtual screen on each side.
- When virtual screens are added or removed, macOS arranges the screens the way their
  panels sit, so moving the mouse off the right edge of one screen lands on the panel to its
  right. Moving panels afterwards doesn't rearrange anything; run **"Arrange Screens Like
  Panels"** (menu or palette) when you want the mouse to follow the new layout, or arrange
  them yourself in System Settings → Displays.
- Removing a panel (⌫) removes its virtual screen. Virtual screens only exist while
  LumaSpace runs: when it quits, macOS moves their windows back to the Mac screen, and the
  next launch recreates them.
- This uses a macOS feature Apple doesn't document (the same one BetterDisplay and DeskPad
  use), so a future macOS update could break it.

### Game mode

**⌃⌥G** (or "Game Mode" in the menu) turns the glasses into a plain 120 Hz monitor for
gaming: LumaSpace stops drawing on them, so the picture stays fixed in the glasses instead
of in space, with no extra delay. The glasses become the main display while it's on, so
fullscreen apps open there and only there, and Steam Big Picture opens if Steam is installed.
The Mac's menu bar and Dock move to the glasses too (behind the game).

Press **⌃⌥G** again to get your screens back; the main display and refresh rate go back to
what they were (60 Hz unless you picked another rate in LumaSpace). Quitting LumaSpace or
unplugging the glasses also ends game mode.

### In the simulator preview

- **⌥-drag** or right-drag: look around.
- Click a screen to select it, drag to move it, scroll to resize it.
- Keys: **R** recenter, **A** add, **⌫** remove selected, **G** group all, **U** ungroup,
  **S** snapping.

Your layout is saved automatically to
`~/Library/Application Support/LumaSpace/layout.json`. If that file gets damaged,
LumaSpace starts with a single screen and keeps the old file as `layout.json.bad`.

## Troubleshooting

First run `/Applications/LumaSpace.app/Contents/MacOS/LumaSpace --diagnose` — it shows which
step fails.

- **Menu says "Simulator — VITURE SDK not found"**: the SDK wasn't bundled. Put the SDK zip
  in `~/Downloads` and rerun `scripts/bundle.sh --install`.
- **"Simulator — Glasses not connected"** with the glasses plugged in: quit SpaceWalker,
  replug the cable, and check `--diagnose` lists the device as "accepted by SDK".
- **Glasses connected but still in the preview**: the glasses must be an extended display
  (System Settings → Displays). LumaSpace looks for a display whose name contains "VITURE".
- **Screens show only their name, not their content**: Screen Recording permission is missing — allow it and reopen. Each
  rebuild is a new ad-hoc signature, so macOS may ask again after `scripts/bundle.sh`.
- A screen shows **"Source unavailable"** when its window was closed or its display
  unplugged; remove it with ⌫ or put the source back.

## Hardware test checklist

These haven't been verified on real glasses yet — please report back:

- [ ] The menu shows "Connected — <your glasses' name>"
- [ ] Screens stay fixed in space when turning your head (and don't drift over a few minutes)
- [ ] ⌃⌥R recenters in front of you
- [ ] Brightness/volume buttons on the glasses update the menu sliders, and the sliders change the glasses
- [ ] Refresh Rate 60 / 90 / 120 Hz switches the glasses' mode
- [ ] ⌃⌥ grab-and-move feels right (speed is 0.1° per point of mouse travel)
- [ ] Unplugging falls back to the simulator; replugging reconnects
- [ ] Triple (⌃⌥3): the mouse moves from the Mac screen into the virtual screens on both sides
- [ ] Game mode (⌃⌥G): glasses at 120 Hz, Big Picture opens on the glasses only; ⌃⌥G again brings the screens back

## Development

```sh
scripts/checks.sh      # LumaCore checks (no XCTest needed)
scripts/bundle.sh      # build build/LumaSpace.app
```

Debug environment variables: `LUMA_LAYOUT=/path.json` (use another layout file),
`LUMA_SNAPSHOT=/path.png` (+ `LUMA_SNAPSHOT_FRAME=N`: write a rendered frame and quit),
`LUMA_SIM_YAW=20` (turn the simulated head), `LUMA_DEMO=triple-drag|palette`,
`LUMA_SDK_PATH` (use a specific `libglasses.dylib`).
