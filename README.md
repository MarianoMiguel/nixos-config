# NixOS Config

Personal NixOS workstation and installer configuration.

## Systems

- `#standard`: portable workstation install for new machines.
- `#bonhart`: same workstation profile with Bonhart-specific runtime fixes.
- `#balerion`: gaming PC profile for the Intel 13900KF and RTX 3080 Ti.
- `#balerion-install`: Balerion with the guided installer's encrypted disk layout.
- `#bonhart-install`: Bonhart with encrypted root plus 64 GiB hibernation swap.
- `#installer`: graphical guided installer ISO carrying both complete systems.

The `#balerion` output keeps its existing storage configuration. Bonhart now uses
the guided installer's encrypted LVM layout by default. After a guided install,
the installer also saves the selected encrypted layout as that machine's local
`storage.nix`, which is intentionally not committed.

## Build The Installer

```sh
./scripts/build-installer-iso.sh
```

The script evaluates the complete flake, builds both existing machine outputs and
both encrypted install outputs, then builds from the literal current workspace
(including new files not committed yet). It prints the finished ISO path under
`result-installer/iso/`. Set `SKIP_VALIDATION=1` only for an intentional ISO-only
rebuild.

To write the ISO to a USB drive and use the remaining space for payload files:

```sh
sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/<usb-disk> result-installer/iso/mariano-nixos-installer.iso /path/to/mariano-personal-payload.tar.zst
```

## Install A Machine

Boot the custom installer in UEFI mode. The guided installer opens automatically;
the desktop shortcut or this command reopens it:

```sh
sudo install-mariano-nixos
```

The wizard asks for:

1. Balerion or Bonhart.
2. The whole target disk. The booted installer disk is excluded.
3. A LUKS disk-unlock password.
4. Mariano's login password.
5. A separate administrator password used by `sudo`.
6. An exact final erase confirmation.

The selected disk is completely erased. Balerion receives a 1 GiB UEFI partition
and an encrypted ext4 root. Bonhart receives the same UEFI partition plus one
encrypted LVM container with a 64 GiB hibernation swap volume and an ext4 root.

The ISO includes the pinned flake inputs, Disko scripts, and both complete target
system closures. Installation therefore runs with Nix offline and does not depend
on a binary-cache download. Generated NixOS documentation and the man-page cache
are disabled in workstation builds to avoid the documentation derivation that
previously made recovery installs fragile.

### Bonhart kernel and Wi-Fi stability

Bonhart intentionally uses the stock NixOS 6.18 LTS kernel so kernel updates
come from the binary cache. Its MT7925 fixes are packaged separately from the
kernel using the pinned
[`zbowling/mt7925` v1.5.0 driver](https://github.com/zbowling/mt7925/tree/v1.5.0).
Only those Wi-Fi modules rebuild when the kernel ABI changes; the full kernel
does not.

Bonhart also sets the Argentina wireless regulatory domain, disables Wi-Fi
power saving and MT7925 PCI ASPM, and keeps redistributable firmware current
with the pinned NixOS release. The existing AMD `dcdebugmask=0x810` workaround
stays a runtime kernel parameter and therefore does not invalidate the cached
kernel. Workstation systems retain five systemd-boot generations, run weekly
garbage collection for store paths older than 14 days, and automatically
optimise the Nix store.

Bonhart leaves DisplayLink disabled because Synaptics requires
accepting a separate EULA and the driver archive cannot legally be redistributed
inside the ISO. To enable it, accept the vendor terms, add the pinned archive to
the local Nix store, then change `mariano.displaylink.enable` to `true` in the
machine-local `hosts/bonhart/storage.nix` before rebuilding:

```sh
nix-prefetch-url --name displaylink-620.zip 'https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip'
```

After installation, remove the USB drive and reboot. The firmware will ask for
the LUKS password; the desktop uses Mariano's password; `sudo` uses the separate
administrator password.

## GNOME Desktop

GNOME on Wayland is the only installed workstation session and GDM is the only
display manager. GNOME owns networking, Bluetooth, audio, displays, power,
wallpaper, notifications, screenshots, screen recording, locking, and login.
KDE applications such as Dolphin, Krita, and Kdenlive remain installed without
installing a second desktop environment.

`Alt+Space` opens Vicinae. Its GNOME bridge and local companion retain the
window-centering, almost-maximize, and hide-other-apps commands. The AppIndicator
bridge keeps the Tailscale and LibrePods tray integrations available, and the
GNOME CodexBar extension remains installed.

There is no live theme engine or coordinated theme switching. Themeable developer
applications use one fixed Catppuccin Mocha palette: Ghostty (fully opaque),
Alacritty, Neovim, VS Code, tmux, Vicinae, and legacy GTK applications. GNOME
Shell itself remains stock and dark. The Impatience extension applies a 0.25×
animation duration factor, keeping common Shell transitions around 50–75 ms.

Bonhart enables `fprintd`; GDM runs password and fingerprint authentication as
separate conversations so either method remains available. Fingerprints can be
managed from GNOME Settings. Local reminders remain available through
`mariano-reminder interactive` and are delivered by the persistent user timer.

The guided installer installs this same GNOME-only workstation closure,
including Steam, Proton VPN, development tools, and the full application set.

## Personal Payload

Secrets and large personal data are not stored in Nix or committed to git.
Create a payload archive separately:

```sh
./scripts/create-personal-payload.sh /path/to/usb-or-backup
```

If no destination is passed, the script writes to `~/nixos-usb-payload` so it
does not accidentally archive its own output inside `~/Development`.

Restore it after install:

```sh
sudo ./scripts/restore-personal-payload.sh /path/to/mariano-personal-payload.tar.zst /home/mariano
```

The payload includes `~/Development`, SSH keys, nvm/npm state, and selected
developer app auth/config directories when they exist.

## Validate

```sh
nix flake check
nixos-rebuild dry-build --flake .#standard
```
