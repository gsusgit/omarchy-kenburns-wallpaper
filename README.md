# Animated Wallpaper

A soft glow that **breathes** over the wallpaper — the desktop looks faintly alive without anything
moving on top of your windows.

Omarchy 4 (Quattro) plugin, Quickshell + QML. First iteration: read it, tune it, keep it or bin it.

## Why it works with every wallpaper and every theme

It never reads or modifies the wallpaper file, and it does not ship per-wallpaper artwork. The glow
is additive light **tinted with the active theme's accent** (`Color.accent`), so:

* any wallpaper works — the glow sits on top of whatever is there;
* any theme works — the tint follows the accent, including a live theme switch;
* the wallpaper transition (`omarchy-theme-bg-set`, theme reveal) is untouched.

## How it is layered

| wl-layer-shell layer | Who paints there |
|---|---|
| background | `omarchy.background` — the wallpaper |
| **bottom** | **this plugin — the glow** |
| top | the bar |
| overlay | menus, OSD, notifications |

Layer-to-layer order is what guarantees the glow is above the wallpaper and below every window.
Verified with:

```bash
hyprctl layers -j | jq -c '[.[] | .levels."1"[]?.namespace]'   # -> ["gsus-animated-wallpaper"]
```

The surface is **click-through** (`mask: Region { }`, an empty input region) and reserves no screen
space (`exclusionMode: ExclusionMode.Ignore`), so desktop double-clicks still open Omarchy's
background switcher and no window is shoved around.

## Install

```bash
git clone <repo> ~/.config/omarchy/plugins/gsus.animated-wallpaper
omarchy plugin validate ~/.config/omarchy/plugins/gsus.animated-wallpaper   # exits 0
omarchy-shell shell enablePlugin gsus.animated-wallpaper '{}'               # prints "ok"
```

Edits to the plugin directory hot-reload; `omarchy-restart-shell` is the fallback.

## Tune

The knobs are the four `readonly` properties at the top of `Service.qml`:

| Property | Default | Meaning |
|---|---|---|
| `intensity` | `0.16` | peak glow alpha — `0.10` barely there, `0.25` obvious |
| `periodMs` | `11000` | one full breath |
| `frameMs` | `70` | repaint interval (~14 fps) |
| `scale` | `1.3` | bloom size as a multiple of screen width |

`glow.png` is the bloom texture (white radial alpha, tinted at runtime); regenerate with
`./make-glow.py [size]`.

## Disable / remove

```bash
omarchy-shell -q shell setPluginEnabled gsus.animated-wallpaper false   # off, keeps the config
rm -r ~/.config/omarchy/plugins/gsus.animated-wallpaper                 # remove
jq 'del(.plugins[] | select(.id=="gsus.animated-wallpaper"))' ~/.config/omarchy/shell.json ...
```

## Measured cost

A 1920x1080 surface damages itself ~14 times a second (one full-screen layer surface plus one
textured quad — no blur, no shadow, no per-frame shader change). Fine on a desktop; on a laptop,
raise `frameMs` to `140` (still smooth for an 11 s breath) or set `intensity` lower.

## Not in this iteration

* GIF/WebP wallpapers do not animate (Omarchy's renderer uses `Image`, not `AnimatedImage`; that
  file is root-owned).
* No per-wallpaper art, no video wallpapers, no Ken-Burns zoom of the wallpaper image.
* No settings file / IPC — four constants in one QML file.
