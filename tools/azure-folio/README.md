# Azure Folio artwork

Desktop images are rendered from the untouched masters at each output's physical
pixel size, including its rotation. An artwork's `desktopFocus` in `catalog.json`
sets the normalized focal point of an aspect-correct crop. Resize/sharpen happens
before one-pixel Atkinson dithering; the resulting two-color image is never
stretched from a small dither mask. The split login/lock portrait remains separate.

`azure-folio set`, `next` and `restore` prepare one crop for every Niri connector.
Disabled connectors use their preferred mode, so the laptop render is cached
before undocking. All displays use the same art, ink and light/dark selection.
DMS receives their paths in one Folio-owned IPC transaction. The stock global
wallpaper setter still works for personal images.

`FolioSync.qml` debounces Niri output changes and Wayland screen-list/geometry
changes (also covering older Niri versions), then runs `refresh-wallpapers`.
This only refreshes an active Folio wallpaper; it leaves a manually selected
personal wallpaper alone. The usual selection lock serializes changes and
hotplug refreshes. A native-resolution 3840×2400 default remains available for
new displays while their render is prepared, and for the greeter's static catalog.

Renders live in `$XDG_CACHE_HOME/azure-folio/wallpapers` (normally `~/.cache`).
The cache key includes the source content, crop metadata, dimensions and renderer
code. Color variants share a monochrome mask; changing ink doesn't repeat the
expensive dithering. Atomic writes keep DMS from loading incomplete files.
The existing source resolution still limits engraving detail; increasing output
resolution improves pixel placement and framing, not the underlying illustration.

Validation: run `test_render.py` with `AZURE_FOLIO_DATA=assets/azure-folio` and
`test_azure_folio.py` with `AZURE_FOLIO_DATA` pointing to a built package's
`share/azure-folio`. Live checks should inspect a different artwork on every
connector via `wallpaper getFor`, exercise an output change, and restore the
user's original selection afterwards. Avoid repeatedly refreshing the unchanged
image as the only proof of a successful update.
