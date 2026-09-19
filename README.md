# Animated Wallpaper

A wallpaper that is faintly **alive**: the image itself drifts, very slowly. Nothing is painted on
top of it — no haze, no light, no particles, just the picture moving.

Omarchy 4 (Quattro) plugin, Quickshell + QML.

## What it does, in numbers

The move is a **loop**: the zoom travels out to the far pose and back again over `speed` seconds,
along a single cosine. One cosine across the whole loop means zero velocity at both turnarounds and at
the seam where the loop restarts, so the motion can neither stop nor jump. Both halves get exactly half
of `speed`: an earlier version spent three quarters of the loop going out and a quarter coming back, and
the three-times-quicker return read as a jump at the end of the move on a real desktop.

There is **no zoom-direction control**, and that is a decision rather than an omission: with a
symmetric loop, "in" and "out" are the same oscillation half a period apart, so the switch could only
ever choose the pose you happen to start on — invisible within seconds of a loop that never stops. It
was built, lived with, and removed. The loop always runs 1 → `maxZoom` → 1.

**The drift is the move's other axis**, and it is deliberately independent of the zoom: any zoom can
creep any way. `drift` is one of the eight compass points or `center` (no drift at all). Its length is
**fixed at 0.9 of the margin** the zoom opens: a slider for it was tried and removed, because the
visible difference between 30 % and 60 % is small next to the zoom it rides on and the ceiling is what
you want anyway. Because the offset rides on that margin rather than on absolute pixels, the image can
never be pulled inside the window — no combination of zoom and drift can show a black edge. It is also
self-scaling: at zoom 1 there is no drift at all, and a small `maxZoom` simply means a shorter journey.

| Parameter | Default | Range | Meaning |
|---|---|---|---|
| `enabled` | `true` | — | freezes the clock; the wallpaper stays painted |
| `speed` | `40` | **one of five levels**: 20, 30, 40, 50, 60 seconds per loop | how long one whole loop takes, out and back; a **smaller** number is faster. The default is the **middle** level |
| `maxZoom` | `1.15` | **one of five levels**: 1.10, 1.15, 1.20, 1.25, 1.30 | how far it zooms; the 1.30 cap is hard, above it the copy shows its pixels |
| `drift` | `center` | center, left, right, up, down, and the four diagonals | which way the image creeps while the zoom opens |

That is the entire schema. Everything else the plugin used to expose was removed after living with
it — see the History table for what and why.

`speed` and `maxZoom` are levels rather than numbers because the panel walks both with a stepper, and a
stepper cannot represent an arbitrary value: anything else (a hand-edited file, an IPC call, a file
from an older schema) is **snapped to the nearest level, ties going up**, so the file, the panel and
the engine always agree on which level is selected. `speed` holds the loop **period in seconds** — the
panel calls the control SPEED, and the panel's speed index runs the other way (see the panel section).

Measured at the defaults on a 1920x1080 desktop: the image edge moves at a **median 8 px/s, peaking
at 11.3 px/s** (the measured peak matches the analytic `maxZoom`·π/`speed` exactly), and the zoom
sweeps the full **1.0000 → 1.1500**, i.e. 144 px of edge travel. The drift adds **130 px** of travel
(0.9 of the margin) along whichever axis — or diagonal — it is pointed at. **Speed is what makes motion
visible, not size**: the first version moved 2 % over 90 s, which is 0.7 px/s at the edge, and no eye
catches it. Raising `speed` is the calm knob.

`omarchy-shell` costs **5.9 %** of one core with the plugin on and **3.9 %** off — about **+2 %** at
~14 fps, no blur and no per-frame shader change. The whole feature adds no timers: one clock drives
everything.

## How it works

We paint the current wallpaper ourselves (`Image` + `PreserveAspectCrop`, read from
`~/.local/state/omarchy/current/background`) instead of letting Omarchy's background plugin do it,
because that is the only way the image itself can move. Two consequences worth knowing:

* **Omarchy's own surface stays underneath as a perfect fallback** — same file, same crop, same
  scale. If this plugin is disabled, crashes, or an image fails to load, the desktop looks exactly
  as it did before; it never goes black.
* **Wallpaper changes still look stock.** `inotifywait` on the Omarchy state directory catches a
  change within ~200 ms, and we re-implement Omarchy's own 420 ms slanted reveal (same `slant -0.18`
  mask maths as `omarchy.background`) so a theme switch arrives looking the way it always did. If the
  incoming image never becomes readable, a 4 s timer swaps anyway rather than leaving a stale
  wallpaper on screen.

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

One clock drives everything: a single 14 fps `Timer` advances `clock`, and every animated value is a
pure function of it (`cosineWave(period)`, plus the exposure breath at its own much slower period).
No `NumberAnimation`s, no particle system (Qt's particle system runs its own frame ticker and would
cost several times the repaints).

## Install

```bash
git clone <repo> ~/.config/omarchy/plugins/gsus.animated-wallpaper
omarchy plugin validate ~/.config/omarchy/plugins/gsus.animated-wallpaper   # exits 0
omarchy-shell shell enablePlugin gsus.animated-wallpaper '{}'               # prints "ok"
```

## Settings

`~/.config/omarchy/animated-wallpaper.json` is the single source of truth, and the service is its
only writer — it both reads it (its `FileView` watches the file, so hand edits apply live) and
writes it when the menu applies something.

**Not inside the plugin directory, and that is load-bearing:** the shell watches a plugin's whole
folder and reloads the plugin when anything in it changes. A settings file kept there reloads the
plugin on every save — measured at four reloads per write — which unmaps and remaps the bar panel
mid-interaction. Omarchy's own stateful plugins keep their config outside for the same reason
(`omarchy-lock-style` → `~/.config/omarchy/lock-style.json`).

The file is created with the defaults on first run, so there is nothing to set up:

```json
{
  "enabled": true,
  "speed": 40,
  "maxZoom": 1.15,
  "drift": "center"
}
```

`Settings.js` is the only place defaults, limits and validation live, shared by `Service.qml` (which
applies them) and `Menu.qml` (which edits them). Everything is clamped and whitelisted on read, so a
hand-edited or corrupted file can never break the renderer: unknown keys are dropped (including keys
from an older schema), `maxZoom` stops at 1.30, a `speed` snaps to the nearest of its five levels,
an unknown `drift` falls back to `center`, and unparseable text becomes the defaults.

The same values are reachable from a terminal — which is also how persistence is tested:

```bash
qs ipc call animated-wallpaper status                  # the live config as JSON
qs ipc call animated-wallpaper setSpeed 50               # snapped to the nearest level
qs ipc call animated-wallpaper setDrift upLeft            # "up-left" and "Up Left" work too
qs ipc call animated-wallpaper setMaxZoom 9            # clamped to 1.30 on write
qs ipc call animated-wallpaper reset
```

Add `--pid "$(qs list --all | awk '/Process ID/{print $3; exit}')"` if `qs` cannot find the instance.
The IPC path applies immediately and skips the panel's Apply step — it is the scripting interface,
not the UI.

**Why the write goes through a `Process` and not `FileView.setText`:** measured, `FileView` stops
persisting writes once the file has been modified externally — an `Apply` right after any external
edit never lands, whatever the delay (tested up to 4 s), the file keeps the stale content, and
nothing is logged because `printErrors` is off. That is a silent "Apply did nothing". A one-shot
writer (temp file + rename, JSON passed as an argv entry) is boring and always works: 8/8 writes
after external edits and 5/5 back-to-back Applies, against 1/8 and 0/5 for the `FileView` route. Do
not "simplify" it back.

## Tune

Everything user-facing is in the menu (below) or the settings file. The remaining constants are the
`readonly` properties at the top of `Service.qml`:

| Property | Default | Meaning |
|---|---|---|
| `exposureDepth` / `exposurePeriodMs` | `0.025` / `22000` | the room-light breath |
| `frameMs` | `70` | repaint interval (~14 fps); `140` = ~7 fps, still smooth |
| `revealMs` | `420` | wallpaper-change reveal (matches Omarchy) |

To calm it down: `speed: 45`, `maxZoom: 1.10`.

If the fine detail of a busy illustration shimmers (sub-pixel resampling on stippled line art),
raise `speed` or lower `maxZoom` — that shimmer is the price of a moving image.

## Bar widget

`BarWidget.qml` puts a button in the bar; `Menu.qml` is the settings panel behind it, loaded lazily
by the widget the way Omarchy's own clock plugin does it.

The panel edits a **local draft** and nothing takes effect until **Apply** is pressed: no half-chosen
value can be left live, and "unsaved changes" is a real state rather than a hope. Two signals say so
at once — a `● Unsaved changes` line in the theme accent under the title, and the button itself,
which switches from a dim `Apply` to an accent-filled `Apply changes`. Closing and reopening the
panel keeps the draft, so an unsaved edit is never silently thrown away; the reset button (the ⟳
icon) only loads the defaults *into the panel*, and still needs Apply.

The panel is deliberately small — **Animate** (a switch in the header, next to the reset button,
because it is a transport control rather than a motion setting), then two sections:

| Section | Row | Control |
|---|---|---|
| ZOOM | — | a five-level stepper: `[−] slider [+]` over 1.10× to 1.30×, with five notches on the track |
| SPEED | — | the same stepper over five loop lengths, 60 s down to 20 s |
| DIRECTION | — | a 3×3 diana of nine chips: the eight compass points plus the centre dot, left-aligned, with no label of its own |

Both steppers are **five levels driven by a level index**, and neither shows a number: the notches on
the track are what say how many levels there are and which one you are on, and they move as you press.
The buttons disable themselves at the two ends and carry short tooltips ("Faster", "Less zoom"). Because
the slider is driven by the index rather than by the value, `PanelSlider`'s own integer rounding does
the snapping and a drag can never land between levels — which is also why there is no fractional
`snapToStep` helper any more (it existed to fix up a slider whose `step` the kit ignores).

**SPEED walks its levels backwards on purpose.** The value underneath is a loop period, so the fastest
setting is the shortest duration: the speed index runs 0 (slowest, 60 s) to 4 (fastest, 20 s), and the
slider's right end is the quick one. Writing the period from a speed index is what keeps the button and
the value from contradicting each other — the first version had a "Slower" button that actually
shortened the loop.

The diana is a `Grid` of the kit's own `Button` rather than a `ButtonGroup` (which is a `Row` and
cannot do 3×3). Using the kit's chip is what makes it cheap *and* consistent: it inherits the theme's
borders, selected fill, tooltips and focus for free, and it centres its own content, so a chip wider
than its glyph still reads as a button. A hand-drawn hexagonal or circular control was considered and
rejected — a hexagon has six sides and there are eight directions, and a `Shape`-based control stops
inheriting the theme.

Sliders use their step (1 s / 0.01×) because `PanelSlider` does not apply `step` itself — its mouse
path only rounds when `integer: true`, so without `Settings.snapToStep` a drag would persist values
like `1.1456522623697918` and the unsaved-changes comparison would then flicker on a stray pixel.

```bash
omarchy bar put gsus.animated-wallpaper --section right --before omarchy.monitor   # place it
omarchy bar move gsus.animated-wallpaper --section center                          # move it
omarchy-shell shell summon gsus.animated-wallpaper '{}'                            # open the panel
omarchy-shell shell hide gsus.animated-wallpaper                                   # close it
```

Rows for new controls go in the `Column` in `Menu.qml`; each one edits the draft through
`root.edit(key, value)` and the whole draft is pushed by `root.apply()`.

## Tests

```bash
./tests/settings.test.sh    # 85 cases, seconds    -- the sanitiser, in node
./tests/pose.test.sh        # 27 cases, ~3 min     -- the motion, from the plugin's own trace
./tests/persist.test.sh     # 23 cases, ~70 s      -- write -> disk -> reload -> survives restart
```

`pose.test.sh` asserts against a **pose trace** the service logs while a config loads
(`[animated-wallpaper] pose {...}`, bounded to 90 s so it cannot grow without end). In the trace `t` is
**milliseconds** of the plugin's clock, `seg` is the position in the loop (0..1), `z` is the scale
factor and `x`/`y` are the pan as a fraction of the margin — reading `t` as seconds gives zero speeds
and a measurement that looks like a broken engine. The trace prints
the exact properties the window consumes, which makes the assertions deterministic — a
screenshot-based suite would need this desktop to be idle, and it belongs to a human. It checks that
the loop period is `speed`, that the zoom reaches `maxZoom` and returns to 1.0, that the pose
never jumps at the seam, that neither extreme is dwelt on, that **both halves run at the same pace**
(the regression test for the 3/4–1/4 split), that the zoom follows one cosine across the loop (max
deviation 0.00000 against an independent reimplementation), that the cosine's peak/mean slope is
≈1.56 against 1.00 for a linear ramp, and that the loop always starts from the whole image. The drift
scenarios add the identity that keeps the image safe — the offset is *exactly* `driftLength × (zoom −
1) / 2`, so it can never exceed the margin it rides on — plus that it points the way it was told
(sign-agnostically: the first version of that check only worked for a negative vector and failed a
correct engine), that it travels its configured length, and that it vanishes at the near pose.

**A scenario aborts and retries if the config changes under it.** This desktop belongs to a human, and
the panel's Apply writes the same settings file a scenario just wrote: a second `config:` line inside
the capture window means the trace mixes two configs. That poisoned a run once — every assertion
failed, and the numbers matched the panel's values exactly (0.084 = 1.4·(1.12−1)/2). Retrying is the
honest fix; silently skipping would hide real regressions.

`persist.test.sh` drives the real write path over IPC — the same `set()`/`save()` pair the menu
calls — then restarts the shell and re-reads the config.

**Both suites save the settings file when they start and put it back when they finish**, because they
write the same file the panel writes: wiping a human's settings is not a test's business. (An `Apply`
from the panel *during* a run is the one thing they cannot preserve — they restore what they found.)

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
* The menu's sliders have no keyboard focus yet and the panel cursor does not walk them — mouse only
  for now.

## History

| Version | Change |
|---|---|
| 0.1 | accent-tinted glow breathing over the wallpaper |
| 0.2 | the plugin paints the wallpaper itself, so the image can move (Ken Burns + pan + exposure) |
| 0.3 | amplitudes and speeds raised: 2 % over 90 s (0.7 px/s) was invisible, so it became 7 % over 34 s (~6 px/s) |
| 0.4 | the 0.1 glow removed — a static coloured haze fought the moving image |
| 0.5 | everything additive gone: the glint band and the motes too. The image moving is the entire effect; `glow.png` and `make-glow.py` were deleted with them |
| 0.6 | placeable in the bar: `BarWidget.qml` (button) + `Menu.qml` (small panel with live state and an Animate switch) |
| 0.7 | configurable: the continuous sine becomes a cycle + dwell engine driven by a settings file, with sliders, a direction dropdown and an easing toggle in the menu, an IPC surface, and 43 test cases |
| 0.8 | the panel edits a local draft behind an **Apply** button with visible unsaved-changes feedback; the settings file moved out of the plugin directory (writing it there reloaded the plugin four times per save and unmapped the panel), and slider drags snap to their step |
| 2.0 | motion dynamics: presets, a binary In/Out direction, handheld shake, a breathing loop, and `pauseAtEnd` removed. All four extras were then dropped as redundant — see below |
| **3.0** | **the small version: four values, one cosine, nothing else.** `preset` (a shortcut through the other values, not an effect of its own), `handheld` (a ~50 px wobble on a 40 s traverse read as the wallpaper vibrating rather than as a hand), `breathing` (its "off" state is a hard snap back, its "on" state left the direction switch looking inert) and `smoothEasing` (ease-in-out is simply the better default) are all gone. The loop became symmetric because the 3/4–1/4 split's quicker return read as a jump at the end; the pan layer went with the shake |
| **3.1** | **the drift comes back as an axis of its own** — independent of the zoom, so any zoom can creep any way: a 3×3 diana of nine directions (the four straight, the four diagonals, the centre) plus a `driftLength` slider. Straight-only was built first and rejected for leaving out the diagonals; an angle in degrees and a pair of X/Y ranges were rejected too, because both spend a slider on something one click can say, and degrees needs a second slider for magnitude anyway |
| **3.2** | **`direction` is gone**, because with a symmetric loop "in" and "out" are the same oscillation half a period apart — it could only pick the starting pose. The ZOOM section lost its row label too: the header names it and the slider is the only control there. The test suites now save and restore the settings file instead of leaving their own defaults behind |
| **3.3** | **both controls become five levels walked with `−`/`+` and a slider that jumps between them**: the duration (20/30/40/50/60) and the zoom (1.10–1.30). The schema snaps to a level, because a stepper cannot represent an arbitrary value, and the duration section is called **SPEED** — which is why its index runs backwards against the loop period: "less" is slower. The drift's **length slider goes**, fixed at the 0.9 ceiling, and DIRECTIONS becomes **DIRECTION**, losing its row label and its length row: header, diana, nothing else, flush left |
| **3.4** | **the `duration` key is renamed `speed`**, to match the panel: it still holds the period in seconds, and an older file's `duration` is read as the speed and rewritten under the new name, so nothing breaks. The default moves to the **middle** level (40 s) rather than the fastest, so a fresh install starts where the control sits in the centre |
