{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.optimise.automatic = true;

  # Old boot entries pin their kernels and initrds even after normal Nix store
  # garbage collection. Five generations leave a useful rollback window
  # without letting /boot grow indefinitely.
  boot.loader.systemd-boot.configurationLimit = 5;

  nixpkgs.config.allowUnfree = true;

  # Reach crates.io through the static host, which is not subject to the 403
  # that the download API returns on some networks. See the overlay for why
  # this rebuilds nothing.
  nixpkgs.overlays = [
    (import ../../overlays/crates-io-static-mirror.nix)
  ];

  # Keep workstation builds independent of the generated NixOS manual. The
  # upstream manual remains available online, while this avoids a large and
  # historically fragile documentation derivation during recovery installs.
  documentation.nixos.enable = false;
  documentation.man.cache.enable = false;
}
