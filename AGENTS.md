# Agent notes

Mariano's NixOS configuration: two workstations (`bonhart` laptop, `balerion`
desktop), a guided offline installer, and the desktop they run. Start with
`README.md`; these notes cover what is easy to get wrong.

## Where things are decided

- `README.md`: systems, installer, the desktop's everyday features.
- `DESIGN.md`: design system of the DMS session (Folio).
- `workshop/`: the desktop's direction: one native, coherent desktop in one
  design language, Folio. Never present Pond, Omarchy or other sources as
  styles or looks; they are only where ideas came from. `workshop/README.md`
  is the process and decisions, `workshop/taste.json` what is wanted and not,
  `workshop/looks/` saved looks, `workshop/UPSTREAMS.md` the rules for taking
  code and ideas from upstreams.
- `docs/remote-workstation.md`: Bonhart runs unattended for weeks; read it
  before touching networking, SSH, Tailscale or power.

## Rules

- Commit messages carry no AI attribution: no `Co-Authored-By` or session
  trailers, no mention of the assistant.
- Two shells, one at a time: Folio (`dotfiles/quickshell/folio`, built from
  the studies) and DMS, the fallback. `mariano-shell use folio|dms` switches
  and remembers; niri starts the chosen one. Do not remove DMS, Folio's
  palette (`azure-folio`) or themeport.
- Folio shell work: read `dotfiles/quickshell/folio/README.md` (module
  contract, design rules) and test only in `scripts/folio-harness`, never
  against the live session.
- Pond is a design reference only (`pond-preview`), not a session. Check
  `workshop/taste.json` before proposing anything from Pond or Omarchy: a
  `dislike` there is a decision.
- Looks never change colors; colors belong to Folio's palette and themeport.
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
- `scripts/workshop look apply NAME` changes the owner's live session. Agents
  save looks; they apply one only when asked.
- `scripts/workshop capture <name> --host bonhart-agent --display wayland-N`
  screenshots a session into the current workshop version.
