{
  lib,
  modulesPath,
  pkgs,
  self,
  # Which machines this image can install. The flake instantiates a dual-host
  # image plus one single-host image per machine; a single-host image halves
  # the embedded closure and the time it takes to build and write.
  installerHosts ? [
    "balerion"
    "bonhart"
  ],
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

  targetSystems = lib.getAttrs installerHosts {
    balerion = self.nixosConfigurations."balerion-install";
    bonhart = self.nixosConfigurations."bonhart-install";
  };

  flakeOutPaths =
    let
      collect =
        parent:
        map (
          child:
          [ child.outPath ]
          ++ (if child ? inputs && child.inputs != { } then collect child else [ ])
        ) (lib.attrValues parent.inputs);
    in
    lib.unique (lib.flatten (collect self));

  systemDependencies =
    system:
    [
      system.config.system.build.toplevel
      system.config.system.build.diskoScript
    ];

  offlineDependencies = lib.unique (
    lib.flatten (map systemDependencies (lib.attrValues targetSystems)) ++ flakeOutPaths
  );
  installClosure = pkgs.closureInfo { rootPaths = offlineDependencies; };

  guidedInstaller = pkgs.writeShellApplication {
    name = "install-mariano-nixos";
    runtimeInputs = with pkgs; [
      coreutils
      cryptsetup
      disko
      dosfstools
      findutils
      gnugrep
      gum
      jq
      lvm2
      nix
      nixos-install-tools
      openssl
      parted
      rsync
      shadow
      util-linux
    ];
    text =
      ''
        export INSTALLER_CONFIG_SOURCE=${lib.escapeShellArg repoSource}
        export INSTALLER_AVAILABLE_HOSTS=${lib.escapeShellArg (lib.concatStringsSep " " installerHosts)}
      ''
      + lib.concatMapStrings (
        name:
        let
          upper = lib.toUpper name;
          system = targetSystems.${name}.config.system.build;
        in
        ''
          export INSTALLER_${upper}_SYSTEM=${lib.escapeShellArg system.toplevel}
          export INSTALLER_${upper}_DISKO_SCRIPT=${lib.escapeShellArg system.diskoScript}
        ''
      ) (lib.attrNames targetSystems)
      + ''
        exec ${repoSource}/scripts/install-system.sh "$@"
      '';
  };

  installerDesktop = pkgs.writeText "mariano-nixos-installer.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Install Mariano NixOS
    Comment=Install the encrypted Balerion or Bonhart configuration
    Exec=${pkgs.kdePackages.konsole}/bin/konsole --fullscreen --hold -e /run/wrappers/bin/sudo ${guidedInstaller}/bin/install-mariano-nixos
    Icon=drive-harddisk
    Terminal=false
    Categories=System;
  '';
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-base.nix"
    ../../modules/nixos/nix.nix
  ];

  networking.hostName = "mariano-nixos-installer";

  image.baseName = lib.mkForce (
    "mariano-nixos-installer"
    + lib.optionalString (lib.length installerHosts == 1) "-${lib.head installerHosts}"
  );
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  isoImage.contents = [
    {
      source = repoSource;
      target = "/nixos-config";
    }
  ];
  isoImage.storeContents =
    [ installClosure ] ++ lib.concatMap systemDependencies (lib.attrValues targetSystems);

  environment.etc = {
    "nixos-config".source = repoSource;
    "install-closure".source = "${installClosure}/store-paths";
  };

  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;
  };
  services.displayManager = {
    plasma-login-manager.enable = true;
    autoLogin = {
      enable = true;
      user = "nixos";
    };
  };
  environment.plasma6.excludePackages = [ pkgs.kdePackages.plasma-workspace-wallpapers ];
  programs.kde-pim.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    exfatprogs
    git
    gptfdisk
    guidedInstaller
    kdePackages.konsole
    pv
    vim
    wget
    zstd
  ];

  system.activationScripts.guidedInstallerDesktop = ''
    home_dir=/home/nixos
    desktop_dir=$home_dir/Desktop
    autostart_dir=$home_dir/.config/autostart

    mkdir -p "$desktop_dir" "$autostart_dir"
    ln -sfT ${installerDesktop} "$desktop_dir/install-mariano-nixos.desktop"
    ln -sfT ${installerDesktop} "$autostart_dir/install-mariano-nixos.desktop"
    chown -R nixos:users "$desktop_dir" "$home_dir/.config"
  '';

  documentation.nixos.enable = lib.mkForce false;
  documentation.man.cache.enable = lib.mkForce false;

  users.motd = ''
    Mariano NixOS installer

    The guided encrypted installer opens automatically. To reopen it, run:
      sudo install-mariano-nixos
  '';

  services.openssh.enable = true;

  users.users.nixos.extraGroups = [
    "networkmanager"
    "wheel"
  ];

  system.stateVersion = "25.11";
}
