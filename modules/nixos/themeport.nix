{ pkgs, ... }:

let
  themeportState = "/home/mariano/.local/state/nixos-config/dotfiles/themeport";

  themeport = pkgs.stdenv.mkDerivation {
    pname = "themeport";
    version = "0.2.0";
    src = ../../tools/themeport;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/share/themeport $out/bin
      cp themeport.py $out/share/themeport/
      cp -r templates $out/share/themeport/
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/themeport \
        --add-flags "$out/share/themeport/themeport.py"
    '';
  };

  # Browser aether:// links need a visible confirmation surface. Launch the
  # adapter in the same floating Ghostty class as the normal ThemePort picker;
  # the CLI deliberately ignores upstream's silent=true request.
  themeportAetherHandler = pkgs.writeShellApplication {
    name = "themeport-aether-handler";
    runtimeInputs = [
      pkgs.ghostty
      themeport
    ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: themeport-aether-handler aether://apply?..." >&2
        exit 2
      fi
      exec ghostty --class=themeport.picker -e themeport handle-url "$1" --hold
    '';
  };

  themeportAetherDesktop = pkgs.makeDesktopItem {
    name = "themeport-aether-handler";
    desktopName = "ThemePort Aether Adapter";
    comment = "Review and import Aether theme links with ThemePort";
    exec = "${themeportAetherHandler}/bin/themeport-aether-handler %u";
    icon = "preferences-desktop-theme";
    terminal = false;
    noDisplay = true;
    mimeTypes = [ "x-scheme-handler/aether" ];
    categories = [ "Settings" ];
  };
in
{
  environment.systemPackages = [
    themeport
    themeportAetherHandler
    themeportAetherDesktop
    # Omarchy themes name Yaru-<color> and Adwaita icon variants; ship them so
    # `themeport set` can apply icons.theme without a per-theme rebuild.
    pkgs.yaru-theme
    pkgs.adwaita-icon-theme
    # renders theme preview images inside the fzf picker panes
    pkgs.chafa
  ];

  xdg.mime.defaultApplications."x-scheme-handler/aether" = "themeport-aether-handler.desktop";
  xdg.mime.addedAssociations."x-scheme-handler/aether" = [
    "themeport-aether-handler.desktop"
  ];

  # Browser accent theming, Omarchy-style: a two-key managed policy that both
  # Chromium-family browsers re-read live via --refresh-platform-policy. The
  # The policy file lives in Themeport's writable per-user state so a theme
  # switch applies live without depending on the config checkout location.
  environment.etc."opt/chrome/policies/managed/themeport-color.json".source =
    "${themeportState}/chrome/color.json";
  environment.etc."brave/policies/managed/themeport-color.json".source =
    "${themeportState}/chrome/color.json";
}
