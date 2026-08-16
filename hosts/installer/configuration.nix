{
  lib,
  modulesPath,
  pkgs,
  ...
}:

let
  repoSource = lib.cleanSourceWith {
    src = ../..;
    filter =
      path: _type:
      let
        name = baseNameOf path;
      in
      !builtins.elem name [
        ".direnv"
        ".git"
        "result"
        "result-installer"
      ];
  };

  installBalerion = pkgs.writeShellApplication {
    name = "install-balerion";
    text = ''
      export NIXOS_CONFIGURATION=balerion
      export NIXOS_CONFIG=/etc/nixos-config
      exec /etc/nixos-config/scripts/install-standard-system.sh "$@"
    '';
  };
in

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
    ../../modules/nixos/nix.nix
  ];

  networking.hostName = "mariano-nixos-installer";

  image.baseName = lib.mkForce "mariano-nixos-balerion-installer";
  isoImage.contents = [
    {
      source = repoSource;
      target = "/nixos-config";
    }
  ];

  environment.etc."nixos-config".source = repoSource;

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
    installBalerion
  ];

  users.motd = ''
    Balerion installer

    Connect to the internet, identify the target disk with lsblk, then run:
      sudo install-balerion /dev/disk/by-id/<target-disk>
  '';

  services.openssh.enable = true;

  users.users.nixos.extraGroups = [
    "networkmanager"
    "wheel"
  ];

  system.stateVersion = "25.11";
}
