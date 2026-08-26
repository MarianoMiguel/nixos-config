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
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
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
      codex-desktop-linux,
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
      ];
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
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

        installer = mkSystem [
          ./hosts/installer/configuration.nix
        ];
      };

      nixosModules.workstation = {
        imports = [
          ./profiles/workstation.nix
        ];
      };

      nixosModules."local-web-hosting" = import ./modules/nixos/local-web-hosting.nix;

      packages.${system} = {
        granola = self.nixosConfigurations.bonhart.pkgs.callPackage ./packages/granola-linux { };
        librepods = inputs.librepods-rust.packages.${system}.default;
        mt76-mt7925 =
          self.nixosConfigurations.bonhart.config.boot.kernelPackages.callPackage
            ./packages/mt76-mt7925.nix
            { };
        installerIso = self.nixosConfigurations.installer.config.system.build.isoImage;
      };
    };
}
