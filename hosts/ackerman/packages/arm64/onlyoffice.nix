# ONLYOFFICE Desktop Editors for aarch64: the official arm64 AppImage of v10.0.0 (bonhart runs
# nixpkgs' onlyoffice-desktopeditors 9.1.0, which is x86_64 only). Untested on the Mac.
{
  lib,
  fetchurl,
  appimageTools,
}:

let
  pname = "onlyoffice-desktopeditors";
  version = "10.0.0";
  src = fetchurl {
    url = "https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v${version}/DesktopEditors-arm64.AppImage";
    hash = "sha256-smwKgMov6T22N9Uvn/XLcEUP5e51hQmf6jYStd7PV3U=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraInstallCommands = ''
    install -Dm0444 ${contents}/onlyoffice-desktopeditors.desktop \
      $out/share/applications/onlyoffice-desktopeditors.desktop
    install -Dm0444 ${contents}/onlyoffice-desktopeditors.png \
      $out/share/pixmaps/onlyoffice-desktopeditors.png
    substituteInPlace $out/share/applications/onlyoffice-desktopeditors.desktop \
      --replace-fail 'Exec=desktopeditors %F' 'Exec=onlyoffice-desktopeditors %F'
  '';
  meta = {
    description = "Office suite: documents, spreadsheets and presentations";
    homepage = "https://www.onlyoffice.com/";
    license = lib.licenses.agpl3Plus;
    mainProgram = pname;
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
