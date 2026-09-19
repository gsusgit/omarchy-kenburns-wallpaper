# Animated Wallpaper

A wallpaper that is faintly **alive**: the image itself drifts, the light breathes, dust floats.
Nothing moves *on top of* your windows — it all happens behind them.

Omarchy 4 (Quattro) plugin, Quickshell + QML.

## What it does, in numbers

Everything is scaled by a single dial: `motion` (`0.02` = the shipped 2%).

| Effect | Magnitude | Period |
|---|---|---|
| Ken Burns zoom | 1.000 → 1.070 | 34 s |
| Pan | up to ±44 px, tied to the zoom slack | 47 s |
| Exposure | 0 → 2.5 % darker, then back | 22 s |
| Bloom (accent-tinted haze) | 0 → 14 % alpha, and it wanders across the screen | 9 s |
| Glint (a band of light crossing) | 0 → 7 % alpha | 42 s |
| Motes (dust in the light) | 26 specks, ≤8 % alpha | 40–80 s rise |

**Speed is what makes motion visible, not size.** The first version moved 2 % over 90 s — that is
0.7 px/s at the screen edge, and no eye catches it. The current preset moves the image edge at
~6 px/s, which you can see *and* still reads as calm.

Measured on a 1920x1080 desktop: `omarchy-shell` costs **11.8 %** of one core with the plugin on and
**11.1 %** off — about **+0.8 %**, at ~14 fps, with no blur and no per-frame shader change.

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
| **bottom** | **this plugin — the wallpaper copy, the bloom, the motes** |
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

## Tune

The knobs are the `readonly` properties at the top of `Service.qml`:

| Property | Default | Meaning |
|---|---|---|
| `motion` | `0.07` | the zoom/pan dial: peak zoom is `1 + motion`. `0.03` barely alive, `0.12` obvious |
| `scalePeriodMs` | `34000` | one in-and-out zoom — shorten it (not raise `motion`) to make the motion read faster |
| `panPeriodMs` | `47000` | one pan orbit |
| `panAmount` | `0.65` | fraction of the zoom slack the pan uses; 1.0 is the safe maximum |
| `exposureDepth` / `exposurePeriodMs` | `0.025` / `22000` | the room-light breath |
| `bloomIntensity` / `bloomPeriodMs` | `0.14` / `9000` | the haze |
| `glintOpacity` / `glintPeriodMs` | `0.07` / `42000` | the travelling light band |
| `moteCount` / `moteAlpha` | `26` / `0.08` | the dust |
| `frameMs` | `70` | repaint interval (~14 fps); `140` = ~7 fps, still smooth |
| `revealMs` | `420` | wallpaper-change reveal (matches Omarchy) |

To calm it down without killing it: `motion: 0.04`, `glintOpacity: 0.04`, `moteAlpha: 0.05`.

If the fine detail of a busy illustration shimmers (sub-pixel resampling on stippled line art),
lengthen `panPeriodMs`, raise `scalePeriodMs` or lower `motion` — that shimmer is the price of a
moving image.

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

## Not in this iteration

* GIF/WebP wallpapers do not animate (Omarchy's renderer uses `Image`, not `AnimatedImage`; that file
  is root-owned).
* No per-wallpaper art, no video wallpapers.
* No cursor parallax (Quickshell 0.3.1 exposes no cursor position) and no audio reactivity yet.
* No settings file: the dials are constants in `Service.qml`.
