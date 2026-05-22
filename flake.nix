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

  outputs = { nixpkgs, nixpkgs-unstable, dms, quickshell, codex-desktop-linux, dms-codexbar, cat-dms, codeIsland-dms, ... }: {
    nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit dms quickshell codex-desktop-linux dms-codexbar cat-dms codeIsland-dms;
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
