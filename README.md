# NixOS Config

Personal NixOS workstation and installer configuration.

## Systems

- `#standard`: portable workstation install for new machines.
- `#bonhart`: same workstation profile with Bonhart-specific kernel tweaks.
- `#balerion`: gaming PC profile for the Intel 13900KF and RTX 3080 Ti.
- `#installer`: graphical Balerion installer ISO carrying the current repo snapshot.

The standard install is intentionally plain UEFI + ext4. It does not configure
LUKS, YubiKey unlock, or host-specific hardware imports.

## Build The Installer

```sh
./scripts/build-installer-iso.sh
```

The script validates Balerion, builds from the literal current workspace
(including new files not committed yet), and leaves the ISO under
`result-installer/iso/`. Set `SKIP_VALIDATION=1` only when a faster ISO-only
rebuild is intentional.

To write the ISO to a USB drive and use the remaining space for payload files:

```sh
sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/<usb-disk> result-installer/iso/mariano-nixos-balerion-installer.iso /path/to/mariano-personal-payload.tar.zst
```

## Install A Machine

Boot the custom installer and run:

```sh
sudo install-balerion /dev/disk/by-id/<target-disk>
```

Use `/dev/disk/by-id/...` for the target disk when possible. The installer
script erases the target disk after an explicit confirmation prompt. Connect
the live installer to Ethernet or Wi-Fi before installing; the ISO carries the
configuration snapshot, while Nix downloads any target packages absent from
the live environment.

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
