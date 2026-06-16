# NixOS Config

Personal NixOS workstation and installer configuration.

## Systems

- `#standard`: portable workstation install for new machines.
- `#bonhart`: same workstation profile with Bonhart-specific kernel tweaks.
- `#installer`: graphical NixOS installer ISO that carries this repo.

The standard install is intentionally plain UEFI + ext4. It does not configure
LUKS, YubiKey unlock, or host-specific hardware imports.

## Build The Installer

```sh
nix build .#installerIso
```

The ISO will be available under `result/iso/` when using a normal Nix
installation. With nix-portable, resolve the store path with
`nix path-info .#installerIso`.

To write the ISO to a USB drive and use the remaining space for payload files:

```sh
sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/<usb-disk> result/iso/mariano-nixos-installer.iso /path/to/mariano-personal-payload.tar.zst
```

## Install A Machine

Boot the custom installer and run:

```sh
sudo /etc/nixos-config/scripts/install-standard-system.sh /dev/disk/by-id/<target-disk> <hostname>
```

Use `/dev/disk/by-id/...` for the target disk when possible. The installer
script erases the target disk after an explicit confirmation prompt.

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
