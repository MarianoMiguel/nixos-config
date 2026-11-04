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
    # DMS's greeter, the login screen until a GDM one is styled to match the
    # disk-unlock screen (modules/nixos/login-screen.nix).
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
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
    # Rex's NixOS module and prebuilt binary (modules/nixos/rex.nix). The
    # preview channel carries tagged builds, not every change, which suits a
    # machine left unattended; Update All moves it with the other inputs.
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
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
      dank-greeter,
      codex-desktop-linux,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      # This configuration's own files, for the copies made from it (the
      # installer's embedded /etc/nixos, the test sandboxes). A `path:`
      # evaluation sees the whole folder, so leave out what never belongs in
      # them: git metadata, agent worktrees (.claude/), build results and the
      # machine-local files .gitignore keeps out (payload archives, direnv).
      repoSource = nixpkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type:
          let
            name = baseNameOf path;
          in
          !(
            builtins.elem name [
              ".git"
              ".claude"
              ".direnv"
              ".envrc"
              ".omo"
              "__pycache__"
              "result"
            ]
            || (type == "directory" && name == "payload")
            || nixpkgs.lib.hasPrefix "result-" name
            || builtins.any (suffix: nixpkgs.lib.hasSuffix suffix name) [
              ".iso"
              ".tar.zst"
              ".tar.zst.age"
              ".manifest.txt"
            ]
          );
      };
      specialArgs = inputs // {
        inherit pkgsUnstable repoSource;
      };
      sharedModules = [
        home-manager.nixosModules.home-manager
        dank-greeter.nixosModules.default
        {
          # The commit each generation was built from, for `nixos-version
          # --configuration-revision` and Update All's list of what changed
          # since the deployed generation. A build from a folder (`path:`) has
          # no commit and records none.
          system.configurationRevision = self.rev or self.dirtyRev or null;
        }
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
                git
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
              cp -r ${repoSource} src
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
        )
        // {
          # The boot look: what may cross into the boot files, the archive and
          # the initrd's check of it (packages/plymouth-folio/test_boot_look.py).
          interstellar-boot = (pkgs.callPackage ./packages/plymouth-folio { }).tests;
        };

      packages.${system} = {
        cmux-browser = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/cmux-browser.nix { };
        granola = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/granola-linux { };
        virtualhere-client = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/virtualhere-client.nix { };
        fido-bridge = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/fido-bridge.nix { };
        librepods = inputs.librepods-rust.packages.${system}.default;
        qt-interstellar-decorations =
          self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/qt-interstellar-decorations
            { };
        installerIso = self.nixosConfigurations.installer.config.system.build.isoImage;
        installerIsoBalerion =
          self.nixosConfigurations."installer-balerion".config.system.build.isoImage;
        installerIsoBonhart =
          self.nixosConfigurations."installer-bonhart".config.system.build.isoImage;
      };
    };
}
