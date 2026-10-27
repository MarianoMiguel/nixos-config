# Agent notes

Mariano's NixOS configuration: two workstations (`bonhart` laptop, `balerion`
desktop), a guided offline installer, and the desktop they run. Start with
`README.md`; these notes cover what is easy to get wrong.

## Where things are decided

- `README.md`: systems, installer, the desktop's everyday features.
- `DESIGN.md`: design system of the DMS session (Azure Folio).
- `workshop/`: the desktop's direction. The target is Pond's look, Omarchy's
  features and NixOS underneath. `workshop/README.md` is the process,
  `workshop/parity.json` the state, `workshop/UPSTREAMS.md` the rules for
  taking code and ideas from upstreams.
- `docs/remote-workstation.md`: Bonhart runs unattended for weeks; read it
  before touching networking, SSH, Tailscale or power.

## Rules

- Commit messages carry no AI attribution: no `Co-Authored-By` or session
  trailers, no mention of the assistant.
- DMS is the default session until the parity board says otherwise. Do not
  remove it, Azure Folio or themeport before then.
- Pond's code comes in through our forks (`MarianoMiguel/pond-interface`,
  `MarianoMiguel/pond-vicinae`). NixOS plumbing belongs in
  `packages/pond-interface.nix` (it fails the build on any unrewritten Arch
  path); behaviour changes are small commits on the fork.
- Never adopt runtime-downloaded code, Hyprland-only code, passwordless sudo,
  or unencrypted installs.
- Don't propose a GNOME-only desktop; it was tried and reverted.

## Building and testing

- The Mac has no Nix. Build on Bonhart over `ssh bonhart-agent`, in a copy:
  `rsync -a --exclude=.git ./ bonhart-agent:.cache/pond-workshop/nixos-config/`
  then `nix build path:.#...` there. Bonhart's own checkout
  (`~/Development/personal/nixos-config`, which `/etc/nixos` points to) may
  hold uncommitted local work; leave it alone.
- Activation needs the separate administrator password; agents build and
  hand off. `sudo nixos-rebuild switch --flake /etc/nixos#bonhart` after the
  owner pulls.
- `nix build .#nixosConfigurations.bonhart.config.system.build.pondPreview`
  gives `pond-preview`, Pond in a nested niri window. When running it on the
  live session over SSH, use an empty workspace, then close it and restore
  the previous focus.
- `scripts/workshop capture <name> --host bonhart-agent --display wayland-N`
  screenshots a session into the current workshop version.
