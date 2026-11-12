# The big apps that build from source on aarch64 (no cache hit there), as one switch.
# ackerman's first install is nixosConfigurations.ackerman-core (flake.nix), with this off: only the
# boot and desktop pieces build. The full ackerman generation (the default, on) adds them later with
# nixos-rebuild. Every other host keeps the default, and their systems are unchanged.
{ lib, ... }:

{
  options.mariano.bigApps.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install the big apps: Zed, Krita, Obsidian and Codex Desktop (apps.nix), and LibrePods
      (niri.nix). Off for ackerman's first, core generation.
    '';
  };
}
