{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/bonhart/configuration.nix
      ];
    };
  };
}
