{ dms, pkgs, quickshell, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in

{
  programs.niri.enable = true;

  programs.dank-material-shell = {
    enable = true;
    package = dms.packages.${system}.dms-shell;
    quickshell.package = quickshell.packages.${system}.default;

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
    install -d -m 0755 -o mariano -g users /home/mariano/.config/niri/dms
    for dms_niri_include in outputs.kdl cursor.kdl colors.kdl wpblur.kdl alttab.kdl windowrules.kdl binds.kdl; do
      if [ ! -e "/home/mariano/.config/niri/dms/$dms_niri_include" ]; then
        install -m 0644 -o mariano -g users /dev/null "/home/mariano/.config/niri/dms/$dms_niri_include"
      fi
    done
    install -m 0644 -o mariano -g users ${../../dotfiles/niri/config.kdl} /home/mariano/.config/niri/config.kdl

    install -d -m 0755 -o mariano -g users /home/mariano/.config/DankMaterialShell
    install -m 0644 -o mariano -g users ${../../dotfiles/dms/theme.json} /home/mariano/.config/DankMaterialShell/theme.json

    dms_settings=/home/mariano/.config/DankMaterialShell/settings.json
    dms_settings_tmp="$(mktemp)"
    if [ -f "$dms_settings" ]; then
      ${pkgs.jq}/bin/jq \
        '. + {
          currentThemeCategory: "custom",
          currentThemeName: "custom",
          customThemeFile: "/home/mariano/.config/DankMaterialShell/theme.json"
        }' \
        "$dms_settings" > "$dms_settings_tmp"
    else
      ${pkgs.jq}/bin/jq -n \
        '{
          currentThemeCategory: "custom",
          currentThemeName: "custom",
          customThemeFile: "/home/mariano/.config/DankMaterialShell/theme.json"
        }' > "$dms_settings_tmp"
    fi
    install -m 0644 -o mariano -g users "$dms_settings_tmp" "$dms_settings"
    rm -f "$dms_settings_tmp"

    install -d -m 0755 -o mariano -g users /home/mariano/.local/state/DankMaterialShell
    dms_session=/home/mariano/.local/state/DankMaterialShell/session.json
    dms_session_tmp="$(mktemp)"
    if [ -f "$dms_session" ]; then
      ${pkgs.jq}/bin/jq \
        '. + {
          weatherLocation: "Campana, Buenos Aires, Argentina",
          weatherCoordinates: "-34.16327,-58.95919"
        }' \
        "$dms_session" > "$dms_session_tmp"
    else
      ${pkgs.jq}/bin/jq -n \
        '{
          weatherLocation: "Campana, Buenos Aires, Argentina",
          weatherCoordinates: "-34.16327,-58.95919"
        }' > "$dms_session_tmp"
    fi
    install -m 0644 -o mariano -g users "$dms_session_tmp" "$dms_session"
    rm -f "$dms_session_tmp"
  '';
}
