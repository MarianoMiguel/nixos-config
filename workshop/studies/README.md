# Studies

HTML studies are where a screen gets designed before any QML is written:
settings, appearance, wallpapers, screensaver, themes, or a component like
Focus, quota or VPN. Azure Folio's colors, Pond's form.

- One folder per screen or taste item: `studies/<id>/v<N>.html`. Never overwrite
  a version; copy it to `v<N+1>.html` and change that.
- Self-contained: link `../_kit/pond.css` for Pond's metrics and motion and use
  `../../captures/...` for reference screenshots. No CDNs, so studies still
  open in ten years.
- Show every state the screen needs (default, hover, active, error,
  empty), side by side, at Pond's real sizes.
- Register each version in `index.json` so the workshop page lists it:

```json
{ "id": "focus", "title": "Focus card", "version": 1, "file": "focus/v1.html",
  "date": "2026-10-28", "notes": "Stay awake, silence, reminders in one sidebar card" }
```

An HTML study is not QML. The final check is always a capture of the real
session (`scripts/workshop capture`).

## The kit and the rules it learned

Every study links `_kit/folio.css` (tokens, materials, controls, motion) and
`_kit/folio.js` (icons, the plate renderer, develop/bleed/leaf/stamp, marquee,
clock). Plates are Folio's 1-bit masks in `_kit/plates/`, printed live in any
ink and mode. Open studies through `scripts/workshop open`; WebGL will not
load images from `file://`.

- One design language. Never name a style after where it came from.
- Every text slot declares its overflow: `.ellipsis` for names, `.fade` for
  titles beside other things, `.clamp-2` for bodies, `Folio.marquee` for what
  is being watched. Grid tracks holding text are `minmax(0, 1fr)`, never `1fr`.
- Every screen with content has Normal, Stress and Empty states, and is
  checked in all three in light and dark.
- App-provided imagery (icons, album art, avatars) stays as shipped unless the
  user chooses Printed.
- Only living (breathing) plates get their own WebGL context; the rest share
  one, or the page runs out of contexts.
- IDs are unique per page; a section and a canvas sharing one broke Appearance.
