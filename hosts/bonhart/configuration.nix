{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/apps.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/development.nix
    ../../modules/nixos/figma.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/ghostty.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/neovim.nix
    ../../modules/nixos/niri.nix
    ../../modules/nixos/nix.nix
    ../../modules/nixos/tmux.nix
    ../../modules/nixos/users.nix
    ../../modules/nixos/virtualisation.nix
    ../../modules/nixos/wallpapers.nix
  ];

  networking.hostName = "bonhart";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelPatches = [
    {
      name = "btmtk-accept-short-wmt-func-ctrl-events";
      patch = ../../patches/linux-btmtk-func-ctrl-short-event.patch;
    }
  ];

  time.timeZone = "America/Argentina/Buenos_Aires";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      brlaser
      cups-brother-hl1210w
    ];
  };

  system.stateVersion = "25.11";
}
