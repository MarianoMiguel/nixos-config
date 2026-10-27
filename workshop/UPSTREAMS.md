# Upstreams

Where the desktop takes its code, design and ideas from, and how each one flows
in. Watermarks (the last reviewed commit or release) live in `upstreams.json`;
`scripts/workshop digest` reports everything since them.

## Roles

| Upstream | Role | How it flows in |
|---|---|---|
| [Pond](https://github.com/bflycomputer) `pond-interface` | Design reference and the Pond session's actual shell | **Consume**: our fork is a flake input; NixOS fixes are applied at build time |
| Pond `vicinae` fork | Launcher and clipboard | **Consume**: fork as a flake input, built with nixos-unstable's Vicinae recipe |
| Pond `iso-installer` | Release signal only | A new `ROOTFS_SHA256` in `src/backend/model.py` means a new Pond system image worth inspecting |
| [Omarchy](https://github.com/omacom/omarchy) | Feature reference | **Port**: ideas only; its window-aware code imports `Quickshell.Hyprland` |
| DankMaterialShell | Current default shell | **Consume** until the parity board is green, then removed |
| Quickshell, niri | Runtime for both shells | **Consume** via `flake.lock` / nixpkgs |
| NixOS | The base | Generations, pinned inputs, offline installer, LUKS |

`DESIGN.md` describes the DMS session. Inside the Pond session, Pond's
`shell/Theme.qml` is the design source of truth; we do not restyle it.

## Tiers, cheapest first

1. **Consume**: pinned upstream code. An update is `gh repo sync` on the fork,
   `nix flake update <input>`, a build, and a look at the session.
2. **Bridge**: an adapter over an upstream format, so new upstream content
   flows in without code changes.
3. **Port**: rebuilt here. Upstream changes never flow in by themselves.
   Every port records its upstream file in `parity.json` (`repo:path`), so
   the digest can show exactly which ported files changed.

Prefer consume over bridge over port. Patch upstream code at build time
(`packages/pond-interface.nix`) when the change is NixOS plumbing; commit to
our fork only for behaviour changes, and keep those commits small so they
rebase cleanly.

## Never adopt

- Code downloaded at runtime (Omarchy's git plugins, Quattro's plugin loader).
- Installs without full-disk encryption.
- Hyprland-only code.
- Closed pieces: Pond's `pm`, `pond-pm-extension`, the Pond Gramercy font.
- Anything that needs passwordless sudo.

## Pond's Arch packages and their NixOS equivalents

Read from Pond's published system image (rootfs `8236724d…`, 2026-10-22), not
guessed.

| Pond package | Contents | Here |
|---|---|---|
| `pond-shell` 0.1.10 | `/usr/share/pond-interface/shell`, `/etc/xdg/quickshell/pond-shell`, `/etc/skel/.config/niri`, kitty, fastfetch, GTK settings, gschema override | `packages/pond-interface.nix` + `modules/nixos/pond.nix` |
| `pond-lockscreen` 0.1.1 | `lockscreen/`, `Pond.WifiStatus` QML plugin, SDDM greeter conf | Same package; PAM service `pond-lock`; greeter not adopted yet |
| `pond-screenshot` 0.1.0 | `Pond.Screenshot` (+ native drag helper) | Same package |
| `pond-wallpaper` 0.1.1 | `Pond.Wallpaper`, `Pond.Daylight` | Same package |
| `pond-launcher` 0.1.4 | Vicinae fork, `vicinae.service`, `uinput` | `packages/pond-vicinae.nix`, `pond-vicinae.service` |
| `pond-pm`, `pond-pm-extension` | Unified pacman/Flatpak/Nix installer (closed) | Not available; see `app-install` and `updates` in the parity board |
| `pond-plymouth-theme`, `pond-grub-config` | Boot splash, GRUB theme | Deferred / systemd-boot |
| `pond-system-optimizations` 1.4.1 | sysctl, udev, ananicy-cpp, zram, regdomain | Under review, rule by rule |
| `pond-fish-config` | fish, pure prompt, eza, bat, fzf | Not adopted (zsh) |
| `pond-snapper-support` | snapper + grub-btrfs | NixOS generations |
| `linux-pond`, `linux-pond-lts` | Clang/ThinLTO kernels (7.3, 6.18.55) | Not adopted; same 6.18 LTS series |

Pond runs niri 26.04 and Quickshell 0.3.2; this repo runs niri 26.04 and
Quickshell 0.3.1 against Qt 6.11. Pond's C++ QML plugins are built against the
same Qt as Quickshell, which they must match.

## Updating Pond

```sh
scripts/workshop digest                  # read what changed
gh repo sync MarianoMiguel/pond-interface  # fast-forward the fork (also pond-vicinae)
nix flake update pond-interface pond-vicinae
nix build .#pond-interface               # fails on any new unrewritten Arch path
```

Then preview on Bonhart without activating anything:

```sh
nix build .#nixosConfigurations.bonhart.config.system.build.pondPreview
./result/bin/pond-preview                # nested niri window running Pond
```

Capture what changed (`scripts/workshop capture`), update `parity.json`,
`scripts/workshop render`, and when satisfied
`scripts/workshop digest --advance` to move the watermarks.
