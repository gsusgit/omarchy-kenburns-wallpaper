# Animated Wallpaper

A wallpaper that is faintly **alive**: the image itself drifts, very slowly. Nothing is painted on
top of it — no haze, no light, no particles, just the picture moving.

Omarchy 4 (Quattro) plugin, Quickshell + QML.

## What it does, in numbers

The move is a **cycle + dwell**: one traverse takes `duration`, then the image holds still for
`pauseAtEnd`. A **pair** is two cycles — out and back — so every pair ends on the pose it started
from and a fixed direction can never jump.

| Parameter | Default | Range | Meaning |
|---|---|---|---|
| `enabled` | `true` | — | freezes the clock; the wallpaper stays painted |
| `duration` | `20.0` s | 5–120 | one traverse |
| `pauseAtEnd` | `2.0` s | 0–10 | the still window after it |
| `maxZoom` | `1.15` | 1.05–**1.30** | how far it zooms; the 1.30 cap is hard, above it the copy shows its pixels |
| `mode` | `random` | zoomIn, zoomOut, horizontal, vertical, random | direction |
| `smoothEasing` | `true` | — | ease-in-out (cosine) vs linear |

`horizontal` and `vertical` pin the zoom at `maxZoom` and sweep sideways instead — that is what
creates the margin to pan into, at the price of a permanent 15 % crop at the default.

**Speed is what makes motion visible, not size.** The first version moved 2 % over 90 s — that is
0.7 px/s at the screen edge, and no eye catches it. The current default moves the image edge at
several px/s, which you can see *and* still reads as calm. Raising `duration` calms it; the dwell is
what makes it read as deliberate rather than as drift.

Measured on a 1920x1080 desktop: `omarchy-shell` costs **~11.8 %** of one core with the plugin on
and **~11.1 %** off — about **+0.8 %**, at ~14 fps, with no blur and no per-frame shader change. The
configuration adds no timers: the same single clock drives everything.

## How it works

We paint the current wallpaper ourselves (`Image` + `PreserveAspectCrop`, read from
`~/.local/state/omarchy/current/background`) instead of letting Omarchy's background plugin do it,
because that is the only way the image itself can move. Two consequences worth knowing:

* **Omarchy's own surface stays underneath as a perfect fallback** — same file, same crop, same
  scale. If this plugin is disabled, crashes, or an image fails to load, the desktop looks exactly
  as it did before; it never goes black.
* **Wallpaper changes still look stock.** `inotifywait` on the Omarchy state directory catches a
  change within ~200 ms, and we re-implement Omarchy's own 420 ms slanted reveal (same `slant -0.18`
  mask maths as `omarchy.background`) so a theme switch arrives looking the way it always did — it
  just also breathes now. If the incoming image never becomes readable, a 4 s timer swaps anyway
  rather than leaving a stale wallpaper on screen.

| wl-layer-shell layer | Who paints there |
|---|---|
| background | `omarchy.background` — the stock wallpaper (now only a fallback) |
| **bottom** | **this plugin — the wallpaper copy, moving** |
| top | the bar |
| overlay | menus, OSD, notifications |

Layer-to-layer order is what puts us above the wallpaper and below every window. Verify with:

```bash
hyprctl layers -j | jq -c '[.[] | .levels."1"[]?.namespace]'   # -> ["gsus-animated-wallpaper"]
```

The surface is **click-through** (`mask: Region { }`, an empty input region) and reserves no screen
space (`exclusionMode: ExclusionMode.Ignore`), so desktop double-clicks still open Omarchy's
background switcher and no window is shoved around.

One clock drives everything: a single 14 fps `Timer` advances `clock`, and every animated value is
`wave(period)` off it. No `NumberAnimation`s, no particle system (Qt's particle system runs its own
frame ticker and would cost several times the repaints).

## Install

```bash
git clone <repo> ~/.config/omarchy/plugins/gsus.animated-wallpaper
omarchy plugin validate ~/.config/omarchy/plugins/gsus.animated-wallpaper   # exits 0
omarchy-shell shell enablePlugin gsus.animated-wallpaper '{}'               # prints "ok"
```

## Settings

`settings.json` in the plugin directory is the single source of truth, and the service is its only
writer — it both reads it (its `FileView` watches the file, so hand edits apply live) and writes it
when the menu changes something.

```json
{
  "enabled": true,
  "duration": 20.0,
  "maxZoom": 1.15,
  "mode": "random",
  "smoothEasing": true,
  "pauseAtEnd": 2.0
}
```

`Settings.js` is the only place defaults, limits and validation live, shared by `Service.qml` (which
applies them) and `Menu.qml` (which edits them). Everything is clamped and whitelisted on read, so a
hand-edited or corrupted file can never break the renderer: unknown keys are dropped, `maxZoom` stops
at 1.30, an unknown `mode` falls back to `random`, and unparseable text becomes the defaults.

The same values are reachable from a terminal — which is also how persistence is tested:

```bash
qs ipc call animated-wallpaper status                  # the live config as JSON
qs ipc call animated-wallpaper setDuration 45
qs ipc call animated-wallpaper setMode horizontal      # labels work too: "Horizontal"
qs ipc call animated-wallpaper setMaxZoom 9            # clamped to 1.30 on write
qs ipc call animated-wallpaper reset
```

Add `--pid "$(qs list --all | awk '/Process ID/{print $3; exit}')"` if `qs` cannot find the instance.

## Tune

Everything user-facing is in the menu (below) or `settings.json`. The remaining constants are the
`readonly` properties at the top of `Service.qml`:

| Property | Default | Meaning |
|---|---|---|
| `exposureDepth` / `exposurePeriodMs` | `0.025` / `22000` | the room-light breath |
| `frameMs` | `70` | repaint interval (~14 fps); `140` = ~7 fps, still smooth |
| `panSplit` | `0.5` | how much of the zoom slack the horizontal/vertical pan uses; 1.0 is the safe maximum |
| `blendSec` | `2.0` | cross-fade when a `random` pair changes direction |
| `revealMs` | `420` | wallpaper-change reveal (matches Omarchy) |

To calm it down: `duration: 45`, `maxZoom: 1.08`.

If the fine detail of a busy illustration shimmers (sub-pixel resampling on stippled line art),
lengthen `duration` or lower `maxZoom` — that shimmer is the price of a moving image.

## Bar widget

`BarWidget.qml` puts a button in the bar; `Menu.qml` is the small panel behind it, loaded lazily by
the widget the way Omarchy's own clock plugin does it. The panel is the settings UI: live state
(animating or paused, the direction in play, the current zoom, the wallpaper file) and a control per
parameter — **Animate**, a **Duration** slider (5–120 s), a **Zoom level** slider (1.05–1.30×), a
**Pause at end** slider (0–10 s), the **Direction mode** dropdown, the **Smooth motion** toggle and a
**Reset to defaults** button.

Sliders write to the service on every move (so the wallpaper responds while you drag) but only touch
the disk on release — writing on every pixel of a drag would rewrite the file dozens of times a
second.

```bash
omarchy bar put gsus.animated-wallpaper --section right --before omarchy.monitor   # place it
omarchy bar move gsus.animated-wallpaper --section center                          # move it
omarchy-shell shell summon gsus.animated-wallpaper '{}'                            # open the panel
omarchy-shell shell hide gsus.animated-wallpaper                                   # close it
```

Rows for new actions go in the `Column` in `Menu.qml`; each one reads and writes state through
`root.set(key, value)` / `root.flush()`, which go to the service — the same object the wallpaper
animates from.

## Tests

```bash
./tests/settings.test.sh    # 17 cases, seconds    -- the sanitiser, in node
./tests/pose.test.sh        # 14 cases, ~2.5 min   -- the motion, from the plugin's own trace
./tests/persist.test.sh     # 12 cases, ~40 s      -- write -> disk -> reload -> survives restart
```

`pose.test.sh` asserts against a **pose trace** the service logs while a config loads
(`[animated-wallpaper] pose {...}`, bounded to 60 s so it cannot grow without end). The trace prints
the exact properties the window consumes, which makes the assertions deterministic — a
screenshot-based suite would need this desktop to be idle, and it belongs to a human. It checks that
a dwell is really still (`spread = 0`), that the cycle period is `duration + pauseAtEnd`, that
`horizontal`/`vertical` pin the zoom and sweep sideways, that `zoomIn` never pans, that the cosine
ease ramps (peak/mean slope ≈ 1.55 against 1.00 for linear), and that `random` never jumps at a pair
boundary.

`persist.test.sh` drives the real write path over IPC — the same `set()`/`save()` pair the menu
calls — then restarts the shell and re-reads the config.

## Disable / remove

```bash
omarchy-shell -q shell setPluginEnabled gsus.animated-wallpaper false   # off, keeps the config
rm -r ~/.config/omarchy/plugins/gsus.animated-wallpaper                 # remove
jq 'del(.plugins[] | select(.id=="gsus.animated-wallpaper"))' ~/.config/omarchy/shell.json ...
```

## Development note

Editing a local plugin sometimes reloads a **stale compiled component** inside the same shell
process: the file on disk is new, the reload fires, and the log still prints the previous version's
string. Observed twice. If a change appears to be ignored, run `omarchy-restart-shell` — that always
picks it up.

Also: the main window is deliberately **inline** in `Service.qml` rather than a separate file
component. Quickshell's `Variants` delegate model only initialises the model roles (`modelData`) for
delegates it can see, so a separate component silently gets an undefined screen and never maps.

Two more traps this plugin walked into, both worth knowing before adding a widget:

* **Never name a nested panel file `Panel.qml`.** Its root type would be `Panel`, which collides
  with `qs.Ui`'s `Panel` inside the plugin's own directory, and the bar widget then refuses to load
  with `File name case mismatch` — the file name on disk is fine, the *type* is what clashes. This
  plugin's menu is `Menu.qml`.
* **A plugin that declares `bar-widget` *plus* another kind must be removed from `plugins[]` before
  it can be placed in the bar.** The registry finds it there, counts it as already enabled, and
  `omarchy bar put` answers "is on the bar" without ever touching the layout. The order that works:

  ```bash
  omarchy-shell shell setPluginEnabled gsus.animated-wallpaper false
  omarchy bar put gsus.animated-wallpaper --section right --before omarchy.monitor
  ```


## Not in this iteration

* GIF/WebP wallpapers do not animate (Omarchy's renderer uses `Image`, not `AnimatedImage`; that file
  is root-owned).
* No per-wallpaper art, no video wallpapers.
* No cursor parallax (Quickshell 0.3.1 exposes no cursor position) and no audio reactivity yet.
* `duration` is one traverse, not a full round trip: a complete pair takes `2 × (duration +
  pauseAtEnd)`. The menu's sliders have no keyboard focus yet, and the panel cursor does not walk
  them — mouse only for now.

## History

| Version | Change |
|---|---|
| 0.1 | accent-tinted glow breathing over the wallpaper |
| 0.2 | the plugin paints the wallpaper itself, so the image can move (Ken Burns + pan + exposure) |
| 0.3 | amplitudes and speeds raised: 2 % over 90 s (0.7 px/s) was invisible, so it became 7 % over 34 s (~6 px/s) |
| 0.4 | the 0.1 glow removed — a static coloured haze fought the moving image |
| 0.5 | everything additive gone: the glint band and the motes too. The image moving is the entire effect; `glow.png` and `make-glow.py` were deleted with them |
| 0.6 | placeable in the bar: `BarWidget.qml` (button) + `Menu.qml` (small panel with live state and an Animate switch) |
| 0.7 | configurable: the continuous sine becomes a cycle + dwell engine driven by `settings.json`, with sliders, a direction dropdown and an easing toggle in the menu, an IPC surface, and 43 test cases |
