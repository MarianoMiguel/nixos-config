# nixos-26.05 still ships Tailscale 1.98.x, and newer releases need a Go
# toolchain the stable branch does not have, so a version override on the
# stable package does not build. Take the whole package from its own
# nixos-unstable input instead. The NixOS module, the tray service and every
# other pkgs.tailscale reference follow this attribute.
nixpkgs-tailscale: final: prev: {
  tailscale = nixpkgs-tailscale.legacyPackages.${final.stdenv.hostPlatform.system}.tailscale;
}
