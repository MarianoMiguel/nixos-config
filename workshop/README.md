# Desktop workshop

The place where this repo's desktop is developed toward one target: **Pond's
look, Omarchy's features, NixOS underneath**. Everything lives in this folder
and in git, so it survives any tool or AI account.

Decision (2026-10-27): copy Pond's design directly rather than restyle DMS.
Pond's shell runs as a second login session, **Pond**, next to the DMS
session. DMS stays the default until the parity board is green.

## What is here

| File | What it is |
|---|---|
| `parity.json` | The parity board: every capability we rely on, where it comes from, its status. Source of truth. |
| `PARITY.md` | Rendered board for reading on GitHub (`scripts/workshop render`). |
| `sessions.json` | Workshop versions: date, summary, git tag, captures, parity counts. |
| `captures/vN/` | Screenshots of the real session for each version. |
| `studies/` | Versioned HTML studies for components Pond lacks; `_kit/pond.css` holds Pond's tokens. |
| `upstreams.json` | Watermarks: last reviewed commit or release per upstream. |
| `UPSTREAMS.md` | Roles, tiers, never-adopt rules, Pond's Arch package map, update procedure. |
| `digests/` | Saved upstream digests (`scripts/workshop digest --write`). |
| `index.html` | The workshop page: parity, versions with captures, upstreams, studies. |

## Look at it

```sh
scripts/workshop serve        # http://127.0.0.1:8765, on the Mac or any Linux host
scripts/workshop status       # counts in the terminal
```

## Try the Pond session

- Log out, choose **Pond** in the login screen. Its niri config lives in
  `~/.config/pond/niri` (Pond's settings panels write there); the DMS
  session's `~/.config/niri` is never touched.
- Or, from any running session: `pond-preview` opens Pond in a nested niri
  window with throwaway config and state. It never locks or hibernates the
  host.

What is in the session and what is not yet is the parity board.

## A workshop session

1. `scripts/workshop version "what this session is about"`
2. `scripts/workshop digest`: what Pond and Omarchy shipped since last time.
3. Pick parity items. For a component Pond does not have, study it first in
   `studies/<id>/vN.html` (see `studies/README.md`).
4. Build it: plumbing in `packages/pond-interface.nix` or
   `modules/nixos/pond.nix`; behaviour changes as small commits on our fork
   `MarianoMiguel/pond-interface`.
5. Look at it with `pond-preview` or the real session, then
   `scripts/workshop capture <name> --host bonhart-agent`.
6. Update `parity.json` and run `scripts/workshop render`.
7. Commit, then `git tag workshop-vN` and push the tag.
8. When the digest has been dealt with: `scripts/workshop digest --advance`.

## Status rules

- **built** means it is in the session. **verified** means someone used it in
  a real Pond session on hardware; record the date and how in `checked`.
  A nested preview is noted in `checked` but is not verification.
- **deviation** and **rejected** need a reason in `notes`.
- The cut-over to Pond as the default session happens when every item is
  verified, deviation, watching or rejected.
