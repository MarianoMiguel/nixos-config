# Studies

HTML studies are where a component Pond does not have (Focus, quota, VPN,
tray, workspace modes...) gets designed in Pond's language before any QML is
written.

- One folder per parity item: `studies/<parity-id>/v<N>.html`. Never overwrite
  a version; copy it to `v<N+1>.html` and change that.
- Self-contained: link `../_kit/pond.css` for Pond's tokens and use
  `../../captures/...` for reference screenshots. No CDNs, so studies still
  open in ten years.
- Show every state the parity item needs (default, hover, active, error,
  empty), side by side, at Pond's real sizes.
- Register each version in `index.json` so the workshop page lists it:

```json
{ "id": "focus", "title": "Focus card", "version": 1, "file": "focus/v1.html",
  "date": "2026-10-28", "notes": "Stay awake, silence, reminders in one sidebar card" }
```

An HTML study is not QML. The final check is always a capture of the real
Pond session (`scripts/workshop capture`).
