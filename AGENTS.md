# Agent notes

Mariano's NixOS configuration: two workstations (`bonhart` laptop, `balerion`
desktop), the M5 Max MacBook Pro (`ackerman`, aarch64), a guided offline
installer, and the desktops they run. Start with `README.md`; these notes
cover what is easy to get wrong.

## Where things are decided

- `README.md`: systems, installer, the desktop's everyday features.
- `docs/remote-workstation.md`: Bonhart runs unattended for weeks; read it
  before touching networking, SSH, Tailscale or power.
- `docs/folio-boot.md`: the boot and disk-unlock screen.
- The earlier niri desktop (DMS, the Folio shell, the design workshop, Pond)
  is archived on the branch `archive/interstellar-niri`. ackerman ran it again
  on 2026-11-08 (niri with the Folio shell, restored as one unit:
  `modules/nixos/niri-folio.nix` and what it imports, `dotfiles-niri/`); since
  2026-11-09 no host imports that unit, and it stays in the tree as it was.
  The workshop and Pond stay archived.
- `hosts/ackerman/`: the M5 Max's hardware, boot (m1n1), disk, network and
  session. Its bring-up lives in `MarianoMiguel/m5max-linux`.

## Rules

- Commit messages carry no AI attribution: no `Co-Authored-By` or session
  trailers, no mention of the assistant.
- GNOME is bonhart's and balerion's desktop (`modules/nixos/desktop.nix`,
  `gnome.nix`). Extend it with GNOME Shell extensions packaged or pinned in
  this repository (`extensions/`, `packages/gnome-shell-extension-*`,
  `gnome.nix`, `vicinae.nix`), not with another shell or compositor. Vicinae
  is their launcher (Alt+Space) and runs the window-management commands; keep
  its shortcuts as they are.
- ackerman runs stock niri with stock DMS (Mariano, 2026-11-09:
  `hosts/ackerman/session.nix`): DMS's own niri config and binds as `dms
  setup` writes them, DMS on its defaults, no wallpaper, plus only what
  ackerman needs on top (`hosts/ackerman/files/niri/ackerman.kdl`: the GPU and
  panel, motion off, bonhart's input feel, his app keys; `comfort.nix`: keyd's
  Alt remaps, input-remapper, the tablet driver). The session starts at tty1
  through `niri-session-ackerman` (`hosts/ackerman/desktop.nix`). Neither
  Folio nor his Hyprland experiment of the same day (dropped; kept in
  m5max-linux's `archive/`) is on it. Keep it ackerman's alone: no niri or DMS
  in the GNOME machines' modules, and no GNOME modules in ackerman.
- `home.nix` copies `dotfiles/` whole into every system that imports it, so a
  file added there changes bonhart's and balerion's builds. ackerman's desktop
  files go in `hosts/ackerman/files/` (the niri + Folio unit's in `dotfiles-niri/`).
- A change made for ackerman must leave bonhart's and balerion's
  `system.build.toplevel` derivations as they were: compare their `drvPath`
  with `main`'s (`nix-diff` when they differ). Shared modules guard aarch64
  differences so that they change nothing on x86_64 (`apps.nix`).
- The look is Interstellar; Folio and Lumen are its themes, chosen with
  `azure-folio` and applied to apps by themeport. A theme must reach
  everything it can, including the disk-unlock screen, or it does not ship.
  Keep the chain whole: `azure-folio set|next|restore` writes
  `~/.local/state/nixos-config/azure-folio/selection.json`;
  `azure-folio-greeter-state` (themeport.nix) publishes
  `/var/lib/azure-folio/appearance.json`; `interstellar-boot-look`
  (folio-boot.nix) prints it to the boot partition. On ackerman, themeport
  still renders the apps' theme files that `home.nix` links (Ghostty, GTK,
  tmux, Neovim); its stock DMS takes no plate.
- Colors belong to Interstellar's looks (`tools/azure-folio/looks.py`) and
  themeport; do not hard-code palettes elsewhere.
- The login screen of bonhart and balerion is still DMS's greeter in a bare
  niri (`modules/nixos/login-screen.nix`), styled like the unlock screen. It
  stays until a GDM login screen matches it; niri there is only the greeter's
  compositor, never a session.
- GNOME's power settings mirror the hibernate-only logind policy
  (`power.nix`, `remote-workstation.nix`); change them together.
- Never adopt runtime-downloaded code, passwordless sudo, or unencrypted
  installs.

## Building and testing

- The M5 Max builds natively with Nix (on its Arch bridge, then on NixOS):
  ackerman is built on itself, never on bonhart, which only evaluates it
  (`nix eval .#nixosConfigurations.ackerman.config.system.build.toplevel.drvPath`).
- bonhart and balerion build on Bonhart. From elsewhere, work over
  `ssh bonhart-agent`, in a copy:
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
