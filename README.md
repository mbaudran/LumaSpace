# LumaSpace

**Your Mac's screens, floating around you. A free, open-source spatial desktop for VITURE Luma glasses.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-arm64-black)
![Swift 6](https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift&logoColor=white)
![No Xcode needed](https://img.shields.io/badge/Xcode-not%20required-blue)
[![MIT License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

LumaSpace turns VITURE Luma glasses into a multi-monitor workspace. Put up to four extra
screens around you, move the mouse between them like real monitors, and arrange the layout
by looking and dragging. One shortcut switches the glasses to a plain 120 Hz screen for gaming.

It's a small menu-bar app built on VITURE's official SDK, and it works without SpaceWalker.

---

## Highlights

- **🖥 Real extra monitors.** Virtual screens are actual macOS displays. Drag windows onto
  them, go fullscreen on them, and move the mouse from one to the next.
- **🧭 Screens fixed in space.** Turn your head and the screens stay where you left them.
  Recenter with one shortcut.
- **✋ Look, grab, drop.** Hold ⌃⌥, look at a screen and move the mouse to place it. Screens
  snap edge to edge.
- **📐 One-key layouts.** Single, Dual, Triple, Stacked, Ultrawide and Coding. Dual and
  Triple create the extra screens for you.
- **🎮 Game mode.** ⌃⌥G hands the glasses over to Steam Big Picture at 120 Hz: fixed in
  view, with no added delay, shown only on the glasses.
- **🎬 Cinema mode.** ⌃⌥C puts any window or display on a giant screen in 3D: in a premium
  movie theater lit by the film, or floating in the dark with its light glowing around it.
- **⌨️ Keyboard first.** Global shortcuts plus a command palette (⌃⌥Space) for everything.
- **🪟 Any window or display.** Pin a single app window or your Mac's own screen as a panel.
- **💡 Glasses controls.** Brightness, volume and refresh rate from the menu bar.
- **🧪 Simulator.** Plan layouts at your desk without the glasses on.

## Requirements

| | |
|---|---|
| Glasses | VITURE **Luma** |
| Mac | Apple silicon (M1 or later), macOS 14 Sonoma or later |
| Tools | None for the download. To build from source: Command Line Tools with Swift 6.0+ (no Xcode) |
| SDK | [VITURE XR Glasses SDK for macOS](https://www.viture.com/developer) (free download) |

Luma tracks rotation only (3DoF): screens stay put when you turn your head, but not when
you lean or walk.

## Install

### Option A: download the app (easiest)

1. Download **LumaSpace-x.y.z.zip** from the
   [latest release](https://github.com/mbaudran/LumaSpace/releases/latest), unzip it and drag
   **LumaSpace.app** into **Applications**.
2. **Open it the first time.** The app isn't notarized by Apple yet, so macOS blocks it at
   first. Try to open it, then go to System Settings → Privacy & Security, scroll down and
   click **Open Anyway**. If you'd rather use Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/LumaSpace.app
   ```
3. **Add the VITURE SDK.** Download *VITURE XR Glasses SDK for macOS* from
   [viture.com/developer](https://www.viture.com/developer). It's free, and it's VITURE's to
   distribute, so it isn't bundled with LumaSpace. Then click the 👓 icon in the menu bar,
   choose **Set Up VITURE SDK…** and pick the zip you just downloaded. You only do this once.
4. Continue with [First launch](#first-launch).

### Option B: build from source

You need Apple's Command Line Tools with Swift 6.0+ (`xcode-select --install`). Xcode isn't
needed.

```sh
git clone https://github.com/mbaudran/LumaSpace.git
cd LumaSpace
scripts/bundle.sh --install
```

Download the VITURE SDK zip first (see above) and leave it in `~/Downloads` or in the
LumaSpace folder. The build script finds it and builds it into the app.

**Updating:** `git pull`, then run `scripts/bundle.sh --install` again.

### First launch

1. **Quit SpaceWalker.** Only one app can read the glasses' head tracking at a time.
2. **Open LumaSpace.** macOS asks for **Screen Recording** permission (System Settings →
   Privacy & Security → Screen Recording). LumaSpace needs it to show your screens in the
   glasses. Allow it, then reopen the app.
3. **Plug in the glasses.** LumaSpace finds them within a couple of seconds, goes fullscreen
   on the glasses and centres the layout in front of you.

## Getting around

Everything lives under the **👓 icon** in the menu bar and in the **command palette**
(**⌃⌥Space**): type a few letters, such as `tri`, `rec` or `bri+`, and press ↩.

### Shortcuts (work from any app)

| Shortcut | Action |
|---|---|
| ⌃⌥Space | Command palette |
| ⌃⌥R | Recenter in front of you |
| ⌃⌥1 … ⌃⌥6 | Layout: Single, Dual, Triple, Stacked, Ultrawide, Coding |
| ⌃⌥N | New virtual screen |
| ⌃⌥A | Add a window or display |
| ⌃⌥G | Game mode on/off |
| ⌃⌥C | Cinema mode on/off |
| ⌃⌥= / ⌃⌥- | Screens closer / farther |
| ⌃⌥] / ⌃⌥[ | Selected screen bigger / smaller |
| ⌃⌥F | Smooth Follow on/off |
| ⌃⌥B / ⌃⌥⇧B | Brightness up / down |

If another app already uses one of these, the menu shows "Shortcut … unavailable".

### Arranging screens

- **Hold ⌃⌥** and look at a screen. A blue ring marks the centre of your view and that
  screen is grabbed. Move the mouse to move it, and let go to drop it.
- Screens **snap** edge to edge with their neighbours and to a 5° grid. Turn this off with
  "Snapping".
- Layouts move as one group. Use **Ungroup Selected** to move a single screen, and **Group All
  Screens** to join them again.
- Your layout is saved automatically and restored the next time you open LumaSpace.

### Virtual screens

Each screen in the glasses shows one of three things: your Mac's display, a single app
window, or a **virtual screen**. A virtual screen is an extra 1920×1080 (Retina) monitor
that LumaSpace creates, and macOS treats it like a plugged-in display.

- **⌃⌥N** adds one where you're looking. You can have up to four.
- **Dual** and **Triple** fill their empty slots with virtual screens. Triple puts your Mac's
  screen in the middle with one on each side.
- When screens are added or removed, macOS lines them up the way they sit in the glasses.
  Moving the mouse off the right edge of one screen then lands on the screen to its right.
  If you rearrange screens later, run **Arrange Screens Like Panels** to line them up again,
  or arrange them yourself in System Settings → Displays.
- **⌫** removes the selected screen. Virtual screens exist only while LumaSpace runs. When
  you quit, macOS moves their windows back to your Mac's screen, and the next launch
  recreates them.

### Game mode

**⌃⌥G** turns the glasses into a plain 120 Hz monitor for games:

- LumaSpace stops drawing, so the picture is fixed in view and has no added delay.
- The glasses become the main display, so fullscreen games open there and only there.
- **Steam Big Picture** opens automatically if Steam is installed.

Press **⌃⌥G** again to get your screens back. The main display and refresh rate return to how
they were. Quitting LumaSpace or unplugging the glasses also ends game mode.

### Cinema mode

**⌃⌥C** shows one window or display on a big screen in 3D:

- It uses the selected screen's window or display; with none selected, you pick one.
  Play a movie in any app (browser, IINA, VLC…) and watch it there.
- The glasses switch to 3D side-by-side mode, so the space has real depth.
- **Cinema → Environment** picks where you watch:
  - **Theater** (default): a premium cinema with stadium rows of black leather recliners,
    acoustic fabric walls with warm LED strips, lit step lights and a dark carpet. The film
    lights the hall: the seats catch its colours, they cast soft shadows on the rows behind,
    and the room glows faintly with the picture. The house lights are up when you enter and
    dim after a few seconds.
  - **Void**: the screen floats in the dark and its light spills around it: a soft halo in
    its colours, a faint haze, specks of dust in the beam, and a glossy black floor that
    reflects the picture.
- The lenses darken (electrochromic tint) so your real room fades away, and go back to how
  they were when cinema mode ends.
- **⌃⌥=** / **⌃⌥-** move you a row closer or farther (in the void: 5–12 m), **⌃⌥]** /
  **⌃⌥[** make the screen bigger or smaller. **Cinema → Ambience** switches between Off
  (just the screen's light), Soft and Full (theater: house lights up, haze and a projector
  beam carrying the picture).
- If the screen looks doubled, adjust **Cinema → Eye Distance** (55–75 mm).

Press **⌃⌥C** again to get your screens back at the previous refresh rate. Quitting LumaSpace
or unplugging the glasses also ends cinema mode.

**Testing it on glasses:** if you see two squeezed copies of the theater side by side instead
of one 3D picture, the glasses didn't switch to 3D. Run `LumaSpace --diagnose` while cinema
mode is on and send the "glasses display mode" line (3840 px wide means 3D worked). If it
stutters, run `LumaSpace --cinema-bench` and send its output: it prints how long a frame takes
on your Mac (90 Hz leaves 11 ms).

### Simulator

Without glasses, LumaSpace runs in a preview window so you can set up layouts at your desk:

- **⌥-drag** or right-drag to look around.
- Click a screen to select it, drag it to move it, and scroll to resize it.
- **R** recenters, **A** adds a screen, **⌫** removes one, **G** / **U** group and
  ungroup, and **S** turns snapping on or off.

## Troubleshooting

Start with the built-in check. It reports the SDK, the glasses' USB connection, the
displays, and whether SpaceWalker is running:

```sh
/Applications/LumaSpace.app/Contents/MacOS/LumaSpace --diagnose
```

With the glasses plugged in, you want `sdk: loaded`, one device marked "accepted by SDK",
and a `glasses display`.

| Symptom | Fix |
|---|---|
| Menu says **"VITURE SDK not found"** | Choose **Set Up VITURE SDK…** in the menu and pick the SDK zip, or run `LumaSpace --install-sdk ~/Downloads/<sdk>.zip`. From source, run `scripts/bundle.sh --install` again. |
| **"Glasses not connected"** while plugged in | Quit SpaceWalker and replug the cable. `--diagnose` should list the glasses as "accepted by SDK". |
| **"Glasses found but couldn't be opened"** | Another app (usually SpaceWalker) is using them. Quit it; LumaSpace retries by itself. |
| Glasses work but LumaSpace stays in the preview | The glasses must be an extended display, not a mirror (System Settings → Displays). |
| Screens show their name but no picture | Screen Recording permission is missing. Allow it and reopen the app. Rebuilding can make macOS ask again. |
| A screen says **"Source unavailable"** | Its window was closed or its display was unplugged. Remove the screen with ⌫. |
| Build says **"no such SDK"** or fails on Swift | Update the Command Line Tools (`xcode-select --install` or Software Update). Swift 6.0+ is needed. |

## Hardware status

LumaSpace is young. Here's what has been confirmed on real Luma glasses so far:

| Feature | Status |
|---|---|
| Connects to the glasses, screens fixed in space | ✅ Confirmed |
| Virtual screens, moving the mouse between them | ✅ Confirmed |
| Recenter, brightness/volume buttons, refresh rate switching | ⏳ Not yet confirmed |
| Game mode (120 Hz + Steam Big Picture) | ⏳ Not yet confirmed |
| Cinema mode (3D switch, depth, exit back to 2D) | ⏳ Not yet confirmed |
| Cinema ambience (lens tint on and restored, glow comfort, smooth at 90 Hz, floor reflection depth) | ⏳ Not yet confirmed |
| Cinema theater (realism, seat-row depth, smooth at 90 Hz, house lights dimming) | ⏳ Not yet confirmed |
| Unplug / replug recovery | ⏳ Not yet confirmed |

Other VITURE models that the SDK accepts might work but are untested. Luma Ultra's 6DoF
tracking isn't supported yet. Tried something? Open an issue and say how it went.

## Good to know

- **Privacy.** LumaSpace captures your screens only to show them in your glasses. Nothing
  is recorded, saved or sent anywhere.
- **Virtual screens use an undocumented macOS feature.** It's the same one apps like
  BetterDisplay and DeskPad use. It works today, but a future macOS update could change it.
- **Not notarized yet.** Releases are ad-hoc signed, so macOS asks you to allow the app
  once (see [Install](#install)).

## How it works

LumaSpace is about 3,500 lines of Swift with no third-party dependencies:

- **VITURE SDK**, loaded at runtime: head orientation, buttons, brightness, volume and
  refresh rate.
- **ScreenCaptureKit:** captures displays and windows straight into Metal textures.
- **Metal:** draws each screen as a rounded panel in 3D, steered by your head's orientation.
- **CGVirtualDisplay:** creates the virtual screens.
- **Carbon hotkeys:** global shortcuts that don't need Accessibility permission.

```
Sources/
  LumaCore/      layout, snapping, presets, head tracking, display arrangement (no UI, fully checked)
  LumaSpace/     the app: SDK bridge, capture, renderer, menu bar, palette, virtual displays
  LumaChecks/    the test suite
  CGVirtualDisplayShim/   header for the virtual display API
```

## Development

```sh
scripts/checks.sh      # run the test suite (no XCTest or Xcode needed)
scripts/bundle.sh      # build build/LumaSpace.app (add --install to copy it to /Applications)
scripts/release.sh     # build build/LumaSpace-<version>.zip for a GitHub release (never includes the SDK)
```

Debug environment variables:

| Variable | Effect |
|---|---|
| `LUMA_LAYOUT=/path.json` | Use a different layout file |
| `LUMA_SNAPSHOT=/path.png` | Save a rendered frame and quit (`LUMA_SNAPSHOT_FRAME=N` picks the frame) |
| `LUMA_SIM_YAW=20` / `LUMA_SIM_PITCH=-25` | Turn / tilt the simulated head |
| `LUMA_CINEMA=test` / `clip` | Start in cinema mode with colour bars on the screen (`clip`: moving, with a flash every 3 s) |
| `LUMA_AMBIENCE=off` / `soft` / `full` | Override the cinema ambience for this run (not saved) |
| `LUMA_ENVIRONMENT=theater` / `void`, `LUMA_ROW=0…7` | Override the cinema environment and row for this run (not saved) |
| `LUMA_CINEMA_STATS=1` | Log the cinema's GPU time per frame once a second |
| `LUMA_DEMO=triple-drag` / `palette` | Scripted demos for testing without input |
| `LUMA_SDK_PATH=/path` | Load a specific `libglasses.dylib` |

Contributions are welcome. Please run `scripts/checks.sh` before opening a pull request.

## License

LumaSpace is released under the [MIT License](LICENSE). The VITURE SDK isn't part of this
repo and isn't covered by it. The theater's textures come from [ambientCG](https://ambientcg.com)
under CC0 (public domain); see [Resources/Theater/CREDITS.md](Resources/Theater/CREDITS.md).

---

<sub>LumaSpace is an independent community project. It is not affiliated with, endorsed by,
or supported by VITURE. VITURE, Luma and SpaceWalker are trademarks of their respective
owners. The VITURE SDK is distributed by VITURE under its own terms.</sub>
