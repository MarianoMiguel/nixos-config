{ dms, pkgs, pkgsUnstable, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  dmsShell = dms.packages.${system}.dms-shell.overrideAttrs (old: {
    postInstall = old.postInstall + ''
      substituteInPlace $out/share/quickshell/dms/Common/Theme.qml \
        --replace-fail '        Quickshell.execDetached(["mkdir", "-p", stateDir]);' '        Quickshell.execDetached(["mkdir", "-p", stateDir]);
        syncSystemColorScheme(isLightMode);' \
        --replace-fail '    function setLightMode(light, savePrefs = true, enableTransition = false) {' '    function syncSystemColorScheme(light) {
        const scheme = light ? "prefer-light" : "prefer-dark";
        Proc.runCommand("setSystemColorScheme", ["${pkgs.glib}/bin/gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme], () => {});
    }

    function setLightMode(light, savePrefs = true, enableTransition = false) {
        syncSystemColorScheme(light);
'
    '';
  });
in

{
  programs.niri.enable = true;

  programs.dank-material-shell = {
    enable = true;
    package = dmsShell;
    quickshell.package = pkgsUnstable.quickshell;

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
