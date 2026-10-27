{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms.url = "github:AvengeMedia/DankMaterialShell";
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Only DaVinci Resolve comes from this package set. Keep its last known-good
    # 21.0.4 revision fixed: Blackmagic replaced the 21.1 archive in place, so
    # the current nixos-unstable expression fails its source integrity check.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9";
    # Only Tailscale comes from this package set (overlays/tailscale-from-unstable.nix).
    # It tracks nixos-unstable so `mariano-system-update-all` keeps the VPN
    # daemon current; the stable branch lags several releases behind.
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/nixos-unstable";
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    dms-codexbar = {
      url = "github:zakstam/dms-codexbar";
      flake = false;
    };
    cat-dms = {
      url = "github:xi-ve/cat-dms";
      flake = false;
    };
    codeIsland-dms = {
      url = "github:payprays/codeIsland-dms";
      flake = false;
    };
    niri-pip = {
      # Keep the reviewed v0.2.1 source immutable. This is intentionally not a
      # moving tag because the daemon controls compositor windows at runtime.
      url = "github:t1ktakdev/niri-pip/4f2075ce35697169e43889aadd55f0900f1d4710";
      flake = false;
    };
    librepods-rust = {
      url = "github:librepods-org/librepods?ref=linux/rust";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pond's desktop and launcher, through our forks so the reviewed source
    # survives upstream changes. Tracked in workshop/UPSTREAMS.md.
    pond-interface = {
      url = "github:MarianoMiguel/pond-interface";
      flake = false;
    };
    pond-vicinae = {
      url = "github:MarianoMiguel/pond-vicinae";
      flake = false;
    };
    # Pond's runtime: Qt 6.12 and Quickshell 0.3.2 (its QML needs 6.12), plus
    # the Vicinae 0.29 recipe its launcher fork builds with. Only the Pond
    # session uses this set; DMS stays on nixos-26.05.
    nixpkgs-pond.url = "github:NixOS/nixpkgs/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-pond,
      home-manager,
      dank-greeter,
      dms,
      quickshell,
      codex-desktop-linux,
      dms-codexbar,
      cat-dms,
      codeIsland-dms,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      pkgsPond = import nixpkgs-pond { inherit system; };
      specialArgs = inputs // {
        inherit pkgsUnstable pkgsPond;
      };
      sharedModules = [
        home-manager.nixosModules.home-manager
        dms.nixosModules.dank-material-shell
        dank-greeter.nixosModules.default
      ];
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = sharedModules ++ modules;
        };
      mkInstaller =
        hosts:
        mkSystem [
          ./hosts/installer/configuration.nix
          { _module.args.installerHosts = hosts; }
        ];
      standardSystem = mkSystem [
        ./hosts/standard/configuration.nix
      ];
      nixosDevSystem = mkSystem [
        ./hosts/nixos-dev/configuration.nix
      ];
    in
    {
      nixosConfigurations = {
        bonhart = mkSystem [
          ./hosts/bonhart/configuration.nix
        ];

        "bonhart-install" = mkSystem [
          ./hosts/bonhart/install-configuration.nix
        ];

        balerion = mkSystem [
          ./hosts/balerion/configuration.nix
        ];

        "balerion-install" = mkSystem [
          ./hosts/balerion/install-configuration.nix
        ];

        standard = standardSystem;

        # Compatibility aliases for plain `nixos-rebuild --flake .` on this
        # machine before and after this flake's hostname is active.
        nixos = nixosDevSystem;
        "nixos-dev" = nixosDevSystem;

        installer = mkInstaller [
          "balerion"
          "bonhart"
        ];

        # Single-machine images: half the closure, half the squashfs time,
        # half the USB. Use these when the target machine is known.
        "installer-balerion" = mkInstaller [ "balerion" ];
        "installer-bonhart" = mkInstaller [ "bonhart" ];
      };

      nixosModules.workstation = {
        imports = [
          ./profiles/workstation.nix
        ];
      };

      nixosModules."local-web-hosting" = import ./modules/nixos/local-web-hosting.nix;

      # Every tests/*.sh script runs under `nix flake check`. They are
      # hermetic: fake binaries under tests/bin, fixtures under tests/fixtures.
      checks.${system} =
        let
          pkgs = self.nixosConfigurations.bonhart.pkgs;
          lib = pkgs.lib;
          testNames = map (lib.removeSuffix ".sh") (
            builtins.filter (lib.hasSuffix ".sh") (builtins.attrNames (builtins.readDir ./tests))
          );
        in
        lib.genAttrs testNames (
          name:
          pkgs.runCommand "test-${name}"
            {
              nativeBuildInputs = with pkgs; [
                bash
                coreutils
                findutils
                gnugrep
                gnused
                gnutar
                jq
                ncurses
                python3
                ripgrep
                util-linux
                zstd
              ];
            }
            ''
              cp -r ${self} src
              chmod -R u+w src
              cd src
              patchShebangs tests scripts
              # The tests write fake binaries with env shebangs at runtime and
              # the sandbox has no /usr/bin/env; point those at store paths.
              sed -i \
                -e "s|#!/usr/bin/env bash|#!${pkgs.runtimeShell}|" \
                -e "s|#!/usr/bin/env python3|#!${pkgs.python3}/bin/python3|" \
                tests/*.sh
              export XDG_RUNTIME_DIR="$TMPDIR/runtime"
              mkdir -p "$XDG_RUNTIME_DIR"
              bash tests/${name}.sh
              touch "$out"
            ''
        );

      packages.${system} = {
        cmux-browser = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/cmux-browser.nix { };
        granola = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/granola-linux { };
        virtualhere-client = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/virtualhere-client.nix { };
        fido-bridge = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/fido-bridge.nix { };
        librepods = inputs.librepods-rust.packages.${system}.default;
        niri-pip = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/niri-pip.nix {
          src = inputs.niri-pip;
        };
        pond-fonts = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/pond-fonts.nix { };
        pond-vicinae = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/pond-vicinae.nix {
          inherit pkgsPond;
          src = inputs.pond-vicinae;
        };
        pond-interface = pkgsPond.callPackage ./packages/pond-interface.nix {
          src = inputs.pond-interface;
          vicinae = self.packages.${system}.pond-vicinae;
        };
        installerIso = self.nixosConfigurations.installer.config.system.build.isoImage;
        installerIsoBalerion =
          self.nixosConfigurations."installer-balerion".config.system.build.isoImage;
        installerIsoBonhart =
          self.nixosConfigurations."installer-bonhart".config.system.build.isoImage;
      };
    };
}
