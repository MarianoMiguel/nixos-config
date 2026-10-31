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

## Your pictures

Any JPEG, PNG or WebP in `~/Pictures/Folio` becomes a plate of the collection
"Your pictures" (id `mine`). `azure-folio pictures` (Folio's shell runs it
whenever the folder changes; `set`, `next` and `restore` run it when `mine`
is involved) prints each one with `build.masks`, `render.desktop_mask` and
`build.print_plate`, into `$XDG_CACHE_HOME/azure-folio/pictures`, keyed by
content: the same desktop and portrait masks, and the light azure render the
shell prints from. DMS's copy in another ink is printed when that plate is
chosen; per-display crops use `render_cached` as for shipped plates. Pictures
removed from the folder are removed from the store and from DMS's renders.
They are never in the repository or the Nix store.

A sidecar beside a picture, `name.json` or `name.jpg.json`, may hold
`{"focus": [x, y], "title": "…"}`: the point every crop keeps in view (0 to 1
from the top left; 0.5, 0.5 without one) and a title in place of the file
name (at most 80 characters). Anything else in it, or a value out of range,
and it is not used; the catalog lists why, as it lists every file it skipped.

The folder is untrusted: links are never followed, files are read whole only
up to 48 MB, decoded only as JPEG, PNG or WebP and only within 50 megapixels
(Pillow's decompression-bomb guard stays on at that limit), and re-encoded.
Root never reads any of it: `publish` reads the shipped catalog alone, so a
selection of your pictures reaches the greeter as the shipped default plate
(with the owner's theme, mode and color); the boot screen keeps only those
three and its own plate.

Validation: run `test_render.py` with `AZURE_FOLIO_DATA=assets/azure-folio` and
`test_azure_folio.py` with `AZURE_FOLIO_DATA` pointing to a built package's
`share/azure-folio`. Live checks should inspect a different artwork on every
connector via `wallpaper getFor`, exercise an output change, and restore the
user's original selection afterwards. Avoid repeatedly refreshing the unchanged
image as the only proof of a successful update.
