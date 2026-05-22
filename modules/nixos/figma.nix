{ figma-linux-font-helper, pkgs, ... }:

let
  fontHelper = pkgs.rustPlatform.buildRustPackage {
    pname = "figma-linux-font-helper";
    version = "0.1.8";

    src = figma-linux-font-helper;
    cargoHash = "sha256-rJgeD10oGVfEw0WWfHO2vaoAdOHoVVt60B3TWHZjpoo=";

    doCheck = false;
  };
in

{
  environment.systemPackages = with pkgs; [
    figma-linux
    fontHelper
  ];

  systemd.user.services.figma-fonthelper = {
    description = "Font Helper for Figma";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${fontHelper}/bin/font_helper";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  system.activationScripts.figmaFontHelperConfig.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config/figma-linux
    ${pkgs.jq}/bin/jq -n \
      '{
        host: "127.0.0.1",
        port: "44950",
        app: {
          fontDirs: [
            "/run/current-system/sw/share/X11/fonts",
            "/run/current-system/sw/share/fonts",
            "/home/mariano/Fonts",
            "/home/mariano/.local/share/fonts",
            "/home/mariano/.fonts"
          ]
        }
      }' > /home/mariano/.config/figma-linux/settings.json
    chown mariano:users /home/mariano/.config/figma-linux/settings.json
    chmod 0644 /home/mariano/.config/figma-linux/settings.json
  '';
}
