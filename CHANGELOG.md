# Changelog

All notable changes to Ken Burns Wallpaper. Versions match `version` in
`manifest.json` and the Git tags on GitHub.

## v5.1.3 — 2026-10-30

Back to the v5.1.1 code. v5.1.2 is withdrawn.

- Reverts the three v5.1.2 commits ("Ata Ken Burns al modo kenburns",
  "Mantiene el interruptor de Ken Burns apagado", "El panel encuentra el
  servicio dentro de la bandeja").
- Why: v5.1.2 tied the plugin to helper scripts that only existed on the
  author's machine (`~/.local/bin/omarchy-wallpaper-mode` and
  `~/.local/bin/omarchy-theme-bg-next`). Without them the Ken Burns layer never
  became visible and Cycle could not advance, so the plugin did nothing on a
  normal Omarchy install.
- Cycle calls Omarchy's own `omarchy-theme-bg-next` again.

## v5.1.2 — 2026-10-23 (withdrawn)

- Tied Ken Burns to a local "kenburns" wallpaper mode.
- Kept the Ken Burns switch off when turned off from the panel.
- Panel found the service inside the tray.

Do not use: depends on local scripts that are not part of the plugin (see v5.1.3).

## v5.1.1 — 2026-09-26

- Hardened reading and writing of the settings file for the marketplace.
- Trail and Cycle titles use the same colour as the other headings on the cover.

## v5.1.0 — 2026-09-23

- Trail (lagged copies of the photo), crossfade between wallpapers, and the
  defaults shown in the panel.
- README shows only the `preview.png` cover.

## v5.0.0 — 2026-09-20

- Vary and Advance (Cycle) at the loop seam, pause when not visible, and a new
  cover that shows the zoom.

## v4.1.0 — 2026-09-20

- Settings apply instantly; speed redistributed into five steps.
- New listing preview image.

## v4.0.0 — 2026-09-20

- First tagged release.
