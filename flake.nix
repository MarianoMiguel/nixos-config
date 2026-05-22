{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    dms.url = "github:AvengeMedia/DankMaterialShell";
    nixpkgs-unstable.follows = "dms/nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-unstable, dms, ... }: {
    nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit dms;
        pkgsUnstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
      modules = [
        dms.nixosModules.dank-material-shell
        ./hosts/bonhart/configuration.nix
      ];
    };
  };
}
