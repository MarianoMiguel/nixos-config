{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/nixos/hardware-standard.nix
    ../../profiles/workstation.nix
  ]
  ++ lib.optional (builtins.pathExists ./local.nix) ./local.nix;

  networking.hostName = "balerion";

  boot.initrd.availableKernelModules = lib.mkAfter [ "vmd" ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # The 13900KF has no integrated GPU, so Balerion uses the RTX 3080 Ti as its
  # only display device. DRM modesetting is required by Niri and GNOME Wayland.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement = {
      enable = true;
      finegrained = false;
    };
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

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
  nixpkgs.config.permittedInsecurePackages = [ "docker-28.5.2" ];
}
