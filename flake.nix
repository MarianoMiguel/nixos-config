{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    dms.url = "github:AvengeMedia/DankMaterialShell";
  };

  outputs = { nixpkgs, dms, ... }: {
    nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit dms;
      };
      modules = [
        dms.nixosModules.dank-material-shell
        ./hosts/bonhart/configuration.nix
      ];
    };
  };
}
