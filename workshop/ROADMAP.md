# From studies to the desktop

The studies are the spec. Folio becomes real as its own Quickshell shell,
built one surface at a time beside DMS. A surface replaces its DMS
counterpart only when it is better in Normal, Stress and Empty content, in
light and dark. DMS keeps providing services (network, Bluetooth, audio,
power) until Folio owns them. Everything ships through NixOS and the looks.

## Phase 0: configuration (done; needs `sudo nixos-rebuild switch`)

- niri: window motion on springs, soft shadows, windows that develop in and
  lift off (`looks/folio.json`, included as `~/.config/niri/look.kdl`).
- Looks survive rebuilds and Folio palette changes (`modules/nixos/home.nix`,
  `tools/azure-folio/azure_folio.py`).
- Chrome takes its palette from the ink (`tools/themeport/themeport.py`).
- Pond is no longer a login session; `pond-preview` stays as a reference.
- After the rebuild: switch the ink to Azure.

## Status (2026-10-29)

The Folio shell exists: `dotfiles/quickshell/folio` (see its README), packaged
by `packages/folio-shell.nix`, run by `folio-shell.service`, chosen with
`mariano-shell use folio|dms`. Built and tested headless with
`scripts/folio-harness`: wallpaper (the plate shader), bar, island, sidebar,
dock, toasts, screenshot thumbnail, launcher, lock, idle, polkit and the
display guard.

Settings is one window with a page per area (`Modules/SystemSettings`):
Appearance, Displays, Sound, Network, Bluetooth, Power & battery, Keyboard,
Mouse & touchpad, Notifications, Default apps, Storage & drives, About.
Displays arranges the screens, remembers a layout per set of connected
displays (seeded from DMS's profiles) and brings it back on hotplug, with
Night light through wl-gammarelay-rs. Each shell owns its display layout
file; niri includes the chosen one through `shell-outputs.kdl`.

Not yet verified on the real session: clicks and drags, blur, PAM unlock,
polkit, idle, hotplug with real displays, Night light on niri.

## Phase 1: foundations and the living plate

- `Folio.qml`: the kit's tokens (paper, ink, text, radii, motion) as a QML
  singleton, generated from themeport so both sides share one source.
- `Plate.qml`: the kit's plate shader as a `ShaderEffect` (compiled to `.qsb`
  with qtshadertools in Nix), reading Folio's masks from the azure-folio
  package: develop, dissolve, bleed, moving dither, moonlit dark.
- The wallpaper layer: the plate develops at login, moves, dissolves on
  change. Replaces DMS's wallpaper.

Milestone: the desktop wallpaper is a living Folio plate.

## Phase 2: sidebar

Rebuild `dotfiles/dms-plugins/folio-sidebar` to `studies/desktop/v3.html`:
hero clock, tiles, sliders, music with real covers, world clock, calendar,
focus, quota, grouped notifications. It already borrows DMS's services and
the existing plugins (focus, world-clock, codexbar), so this is mostly QML.

## Phase 3: the island

A Quickshell overlay at the bar's centre: clock, MPRIS music and the full
player, focus countdown, recording (`mariano-capture`), volume and brightness
notches (replaces DMS's OSD), message peeks, battery and charging, privacy
dots.

## Phase 4: lock screen

`studies/lockscreen/v1.html`: art and page, the cross grid printing per key,
edge tabs, unlock that lifts the page and opens the art. Either a rewrite of
`patches/dms-azure-folio-lock.patch` or Folio's own `WlSessionLock`.

## Phase 5: bar and dock

Folio's bar (the island in its centre, privacy dots, one status pill) and a
dock that magnifies, never moves for other panels, and shows real icons:
original, plated or printed.

## Phase 6: the rest of a mature desktop

Launcher with actions and previews; the Settings app, Appearance first
(`studies/appearance/v1.html`), then every system area a mature desktop
manages (displays, sound devices, networks, Bluetooth, power, input,
notifications, default apps, drives); screensaver; screenshot thumbnail;
polkit prompts on the cross grid; undo toasts; interface sounds. See the
taste board's `research` items and `digests/2026-10-28-mature-os.md`.

## How each piece is done

study → QML → capture of the real session → Stress and Empty check →
`scripts/workshop version` → commit and tag.

## Risks

- Quickshell 0.3.1 on Qt 6.11: shaders must be precompiled `.qsb`.
- A full-screen shader every frame on Bonhart's iGPU: the moving dither only
  changes 9 times a second, so render on change, not every vsync.
- DMS's plugin and QML interfaces move; pin the flake and smoke-test.
