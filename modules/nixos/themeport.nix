{ pkgs, ... }:

let
  repo = "/home/mariano/Development/personal/nixos-config";

  themeport = pkgs.stdenv.mkDerivation {
    pname = "themeport";
    version = "0.1.0";
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
in
{
  environment.systemPackages = [
    themeport
    # Omarchy themes name Yaru-<color> and Adwaita icon variants; ship them so
    # `themeport set` can apply icons.theme without a per-theme rebuild.
    pkgs.yaru-theme
    pkgs.adwaita-icon-theme
  ];

  # Browser accent theming, Omarchy-style: a two-key managed policy that both
  # Chromium-family browsers re-read live via --refresh-platform-policy. The
  # policy file lives in the repo's writable tier so `themeport set` can swap
  # it without a rebuild; /etc only holds a stable symlink to it.
  environment.etc."opt/chrome/policies/managed/themeport-color.json".source =
    "${repo}/dotfiles/themeport/chrome/color.json";
  environment.etc."brave/policies/managed/themeport-color.json".source =
    "${repo}/dotfiles/themeport/chrome/color.json";
}
