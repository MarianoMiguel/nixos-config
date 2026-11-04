# Azure Folio artwork

Desktop images are rendered from the untouched masters at each output's physical
pixel size, including its rotation. An artwork's `desktopFocus` in `catalog.json`
sets the normalized focal point of an aspect-correct crop. Resize/sharpen happens
before one-pixel Atkinson dithering; the resulting two-color image is never
stretched from a small dither mask. The split login/lock portrait remains separate.

`azure-folio set`, `next` and `restore` (Folio theme) put the chosen plate,
printed in the selection's ink and mode, on GNOME's desktop through
`mariano-set-wallpaper` (modules/nixos/themeport.nix): one native-resolution
3840×2400 picture for every display, which GNOME zooms to fill each. Lumen's
sky was drawn live by the Folio shell; under GNOME a Lumen selection leaves
the desktop's wallpaper as it was. Either way the selection is then published
for the login and boot screens.

`render.render_cached` still renders aspect-correct crops at a given pixel
size into `$XDG_CACHE_HOME/azure-folio/wallpapers` (normally `~/.cache`). The
cache key includes the source content, crop metadata, dimensions and renderer
code. Color variants share a monochrome mask; changing ink doesn't repeat the
expensive dithering. The existing source resolution still limits engraving
detail; increasing output resolution improves pixel placement and framing,
not the underlying illustration.

## Your pictures

Any JPEG, PNG or WebP in `~/Pictures/Folio` becomes a plate of the collection
"Your pictures" (id `mine`). `azure-folio pictures` (and `set`, `next` and
`restore` when `mine` is involved) prints each one with `build.masks`,
`render.desktop_mask` and `build.print_plate`, into
`$XDG_CACHE_HOME/azure-folio/pictures`, keyed by content: the same desktop and
portrait masks, and the light azure render. The desktop's copy in another ink
is printed when that plate is chosen. Pictures removed from the folder are
removed from the store and from any renders of them. They are never in the
repository or the Nix store.

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
`share/azure-folio`. Live checks should choose a different artwork than the
current one, read `gsettings get org.gnome.desktop.background picture-uri`,
and restore the user's original selection afterwards.
