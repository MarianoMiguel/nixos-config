# NixOS Config

Personal NixOS configuration for `bonhart`.

## Apply

```sh
sudo nixos-rebuild switch --flake .#bonhart
```

## Validate

```sh
nixos-rebuild dry-build --flake .#bonhart
```
