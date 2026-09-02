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
    # A real unstable pin. Following DMS's nixpkgs made "unstable" whatever DMS
    # last locked, which trailed the stable pin by months. Only DaVinci Resolve
    # (21, newer than the stable channel's 20.x) comes from here.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
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
      specialArgs = inputs // {
        inherit pkgsUnstable;
      };
      sharedModules = [
        home-manager.nixosModules.home-manager
        dms.nixosModules.dank-material-shell
        dms.nixosModules.greeter
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
        granola = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/granola-linux { };
        librepods = inputs.librepods-rust.packages.${system}.default;
        niri-pip = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/niri-pip.nix {
          src = inputs.niri-pip;
        };
        installerIso = self.nixosConfigurations.installer.config.system.build.isoImage;
        installerIsoBalerion =
          self.nixosConfigurations."installer-balerion".config.system.build.isoImage;
        installerIsoBonhart =
          self.nixosConfigurations."installer-bonhart".config.system.build.isoImage;
      };
    };
}
