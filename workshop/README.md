# Desktop workshop

Where this repo's desktop is designed. The target: **one native, coherent
desktop that feels like its own product**, where every screen (settings,
appearance, wallpapers, screensaver, themes, lock) is designed rather than
stitched together. One design language, **Folio**: paper and ink, soft
rounded form, a printmaker's motion, NixOS underneath. Pond, Omarchy, macOS
and GNOME are sources of ideas, not parts of the design. Everything lives in
this folder and in git, so it survives any tool or AI account.

## Decisions

- **2026-10-28: design our own; Pond is a reference.** Pond's session was
  not ready and much of it was not wanted, so it is no longer a login
  session. What is liked from it (rounded corners, unhurried motion, soft
  depth) comes over as design, not as code. `pond-preview` keeps Pond
  runnable in a window for comparison. Folio's colors stay.
- **2026-10-28: one language.** No look is named after where it came from;
  the desktop has one design, Folio. `before` keeps the pre-revamp look.
- **Open question: how far to move off DMS.** DMS is the runtime today, and
  looks restyle it through the settings it exposes. Where it limits the
  design (its settings window, appearance and wallpaper screens), the screen
  is studied here first; the studies decide whether it can be done in DMS or
  needs our own Quickshell shell.
- 2026-10-27 (superseded): copy Pond directly and retire DMS. The parity
  board from that attempt is in `archive/`.

## What is here

| File | What it is |
|---|---|
| `looks/` | Saved looks: shape, motion, material and depth for the DMS session and niri, never colors. `folio` is the design; `before` is the desktop before the revamp. |
| `taste.json` | The taste board: what the desktop should and should not have (`like`, `unsure`, `dislike`, with notes and where each idea came from). Source of truth for direction. |
| `TASTE.md` | Rendered board for reading on GitHub (`scripts/workshop render`). |
| `studies/` | Versioned HTML studies of screens, designed before any QML is written. |
| `sessions.json` | Workshop versions: date, summary, git tag, look, captures, taste counts. |
| `captures/vN/` | Screenshots of the real session for each version (v1 and v2 are Pond). |
| `upstreams.json`, `UPSTREAMS.md` | Watermarks per upstream; rules for taking code and ideas. |
| `archive/` | The Pond session parity board (2026-10-27). |
| `index.html` | The workshop page. |

## Open it

```sh
scripts/workshop open       # serves in the background and opens the page
scripts/workshop serve      # or in the foreground, on any host: http://127.0.0.1:8765
```

On the page, **Looks** applies a saved look to the running session and
saves what you tuned in DMS Settings as a new one; **Taste** records verdicts
and notes. Both write straight into this folder, so commit when you like
what you have. The same from a terminal:

```sh
scripts/workshop look                     # saved looks; * is live
scripts/workshop look apply before        # back to the desktop before the revamp
scripts/workshop look save mine --note "rounder bar, slower popouts"
scripts/workshop look diff folio          # what the live session changed from the design
scripts/workshop taste set sidebar like --note "but on the left, collapsible"
```

A look writes DMS's `settings.json` (DMS reloads it at once) and
`~/.config/niri/look.kdl`, which `dotfiles/niri/config.kdl` includes after
DMS's files and before the style toggles. `pond-preview` opens Pond in a
nested window to compare motion and screens.

## A workshop session

1. `scripts/workshop version "what this session is about"`
2. `scripts/workshop digest`: what Pond and Omarchy shipped since last time.
   Add what is worth judging to the taste board.
3. Play: apply looks, tune in DMS Settings, save the ones you like. Judge
   `unsure` items in `pond-preview`, the captures or a study.
4. For a screen DMS cannot do well, study it in `studies/<id>/vN.html`
   (see `studies/README.md`), then build it.
5. `scripts/workshop capture <name>` from the session; `scripts/workshop render`.
6. Commit, then `git tag workshop-vN` and push the tag.
7. When the digest has been dealt with: `scripts/workshop digest --advance`.
