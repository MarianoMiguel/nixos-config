{ dms, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in

{
  programs.niri.enable = true;

  programs.dank-material-shell = {
    enable = true;
    package = dms.packages.${system}.dms-shell;
    quickshell.package = dms.packages.${system}.quickshell;

    # dgop is not available in the current nixpkgs pin.
    enableSystemMonitoring = false;

    # The Niri config starts DMS, which keeps it out of the Plasma session.
    systemd.enable = false;
  };

  services.iio-niri.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    libnotify
    playerctl
    swayidle
    swaylock
    wtype
    xwayland-satellite
  ];

  system.activationScripts.niriConfig.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config/niri
    install -m 0644 -o mariano -g users ${../../dotfiles/niri/config.kdl} /home/mariano/.config/niri/config.kdl
  '';
}
