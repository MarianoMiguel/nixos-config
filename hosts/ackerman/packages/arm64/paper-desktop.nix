# Paper (paper.design) for aarch64: the same 0.5.18 build bonhart runs (apps.nix's paperDesktop),
# its official arm64 AppImage (listed in https://download.todesktop.com/2601167vjw8xe/latest-linux-arm64.yml),
# wrapped as apps.nix's wrapDesignAppImage wraps the x86_64 one
{
  lib,
  fetchurl,
  appimageTools,
  makeWrapper,
}:

let
  pname = "paper-desktop";
  version = "0.5.18";
  src = fetchurl {
    url = "https://download.todesktop.com/2601167vjw8xe/paper-desktop-0.5.18-build-261031pthw9s82w-arm64.AppImage";
    hash = "sha256-DQL0Cl/F9Rz9HE7AqMgiLx7GjPk9U/9wZ2aDxYWMXIc=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  nativeBuildInputs = [ makeWrapper ];
  extraInstallCommands = ''
    install -Dm0444 ${contents}/paper-desktop.desktop $out/share/applications/paper-desktop.desktop
    install -Dm0444 ${contents}/paper-desktop.png $out/share/pixmaps/paper-desktop.png
    substituteInPlace $out/share/applications/paper-desktop.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=paper-desktop %U'
    wrapProgram $out/bin/paper-desktop \
      --set FONTCONFIG_FILE /etc/fonts/fonts.conf \
      --add-flags "--no-sandbox \''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';
  meta = {
    description = "Design tool to create, share and ship work";
    homepage = "https://paper.design/";
    license = lib.licenses.unfree;
    mainProgram = pname;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
