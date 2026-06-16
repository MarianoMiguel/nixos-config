{ lib, modulesPath, pkgs, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
    ../../modules/nixos/nix.nix
  ];

  networking.hostName = "mariano-nixos-installer";

  image.fileName = lib.mkForce "mariano-nixos-installer.iso";
  isoImage.contents = [
    {
      source = ../..;
      target = "/nixos-config";
    }
  ];

  environment.etc."nixos-config".source = ../..;

  environment.systemPackages = with pkgs; [
    curl
    dosfstools
    e2fsprogs
    exfatprogs
    git
    gptfdisk
    jq
    parted
    pv
    rsync
    vim
    wget
    zstd
  ];

  services.openssh.enable = true;

  users.users.nixos.extraGroups = [
    "networkmanager"
    "wheel"
  ];

  system.stateVersion = "25.11";
}
