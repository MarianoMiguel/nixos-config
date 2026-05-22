{
  description = "Mariano's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    dms.url = "github:AvengeMedia/DankMaterialShell";
    nixpkgs-unstable.follows = "dms/nixpkgs";
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
  };

  outputs = { nixpkgs, nixpkgs-unstable, dms, quickshell, codex-desktop-linux, ... }: {
    nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit dms quickshell codex-desktop-linux;
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
