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
    figma-linux-font-helper = {
      url = "github:Figma-Linux/figma-linux-font-helper";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, dms, quickshell, codex-desktop-linux, dms-codexbar, cat-dms, codeIsland-dms, figma-linux-font-helper, ... }:
    let
      system = "x86_64-linux";
      hardwareConfigPath =
        let
          configuredPath = builtins.getEnv "NIXOS_HARDWARE_CONFIG";
        in
        if configuredPath != "" then /. + configuredPath else /etc/nixos/hardware-configuration.nix;
      localHardwareConfig = { lib, ... }: {
        assertions = [
          {
            assertion = builtins.pathExists hardwareConfigPath;
            message = "Expected local hardware config at ${toString hardwareConfigPath}. Run nixos-rebuild with --impure so the flake can import the machine's hardware-configuration.nix, or set NIXOS_HARDWARE_CONFIG to a generated hardware config path.";
          }
        ];

        imports = lib.optionals (builtins.pathExists hardwareConfigPath) [
          hardwareConfigPath
        ];
      };
    in
    {
      nixosConfigurations.bonhart = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit dms quickshell codex-desktop-linux dms-codexbar cat-dms codeIsland-dms figma-linux-font-helper;
          pkgsUnstable = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        };
        modules = [
          localHardwareConfig
          dms.nixosModules.dank-material-shell
          dms.nixosModules.greeter
          ./hosts/bonhart/configuration.nix
        ];
      };
      nixosModules.bonhart = {
        imports = [
          dms.nixosModules.dank-material-shell
          dms.nixosModules.greeter
          ./hosts/bonhart/configuration.nix
        ];
      };
    };
}
