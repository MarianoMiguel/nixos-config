{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms.url = "github:AvengeMedia/DankMaterialShell";
    nixpkgs-unstable.follows = "dms/nixpkgs";
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
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, dms, quickshell, codex-desktop-linux, dms-codexbar, cat-dms, codeIsland-dms, ... }:
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
      mkSystem = modules: nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = sharedModules ++ modules;
      };
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

        standard = standardSystem;

        # Compatibility aliases for plain `nixos-rebuild --flake .` on this
        # machine before and after this flake's hostname is active.
        nixos = nixosDevSystem;
        "nixos-dev" = nixosDevSystem;

        installer = mkSystem [
          ./hosts/installer/configuration.nix
        ];
      };

      nixosModules.workstation = {
        imports = [
          ./profiles/workstation.nix
        ];
      };

      packages.${system}.installerIso =
        self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
