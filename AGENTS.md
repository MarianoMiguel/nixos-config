# Agent notes

Mariano's NixOS configuration: two workstations (`bonhart` laptop, `balerion`
desktop), a guided offline installer, and the desktop they run. Start with
`README.md`; these notes cover what is easy to get wrong.

## Where things are decided

- `README.md`: systems, installer, the desktop's everyday features.
- `docs/remote-workstation.md`: Bonhart runs unattended for weeks; read it
  before touching networking, SSH, Tailscale or power.
- `docs/folio-boot.md`: the boot and disk-unlock screen.
- The earlier niri desktop (DMS, the Folio shell, the design workshop, Pond)
  is archived on the branch `archive/interstellar-niri`. Read it there for
  history; do not bring it back piecemeal.

## Rules

- Commit messages carry no AI attribution: no `Co-Authored-By` or session
  trailers, no mention of the assistant.
- The desktop is GNOME (`modules/nixos/desktop.nix`, `gnome.nix`). Extend it
  with GNOME Shell extensions packaged or pinned in this repository
  (`extensions/`, `packages/gnome-shell-extension-*`, `gnome.nix`,
  `vicinae.nix`), not with another shell or compositor. Vicinae is the
  launcher (Alt+Space) and runs the window-management commands; keep its
  shortcuts as they are.
- The look is Interstellar; Folio and Lumen are its themes, chosen with
  `azure-folio` and applied to apps by themeport. A theme must reach
  everything it can, including the disk-unlock screen, or it does not ship.
  Keep the chain whole: `azure-folio set|next|restore` writes
  `~/.local/state/nixos-config/azure-folio/selection.json`;
  `azure-folio-greeter-state` (themeport.nix) publishes
  `/var/lib/azure-folio/appearance.json`; `interstellar-boot-look`
  (folio-boot.nix) prints it to the boot partition.
- Colors belong to Interstellar's looks (`tools/azure-folio/looks.py`) and
  themeport; do not hard-code palettes elsewhere.
- The login screen is still DMS's greeter in a bare niri
  (`modules/nixos/login-screen.nix`), styled like the unlock screen. It stays
  until a GDM login screen matches it; niri there is only the greeter's
  compositor, never a session.
- GNOME's power settings mirror the hibernate-only logind policy
  (`power.nix`, `remote-workstation.nix`); change them together.
- Never adopt runtime-downloaded code, passwordless sudo, or unencrypted
  installs.

## Building and testing

- The Mac has no Nix. Build on Bonhart over `ssh bonhart-agent`, in a copy:
  `rsync -a --exclude=.git --exclude=.claude ./ bonhart-agent:.cache/nixos-config-build/`
  then `nix build path:.#...` there. Bonhart's own checkout
  (`~/Development/personal/nixos-config`, which `/etc/nixos` points to) may
  hold uncommitted local work; leave it alone.
- Activation needs the separate administrator password; agents build and
  hand off. `sudo nixos-rebuild switch --flake /etc/nixos#bonhart` after the
  owner pulls.
- Never test against the owner's live session: no `gsettings`/`dconf`
  writes, no restarts of their user units. `nix build
  .#checks.x86_64-linux.<name>` runs one check (`tests/*.sh`, and
  `interstellar-boot` for the boot look).
