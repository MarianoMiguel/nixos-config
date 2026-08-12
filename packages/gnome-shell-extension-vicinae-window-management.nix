{ lib, stdenvNoCC }:

let
  uuid = "vicinae-window-management@mariano";
in
stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-vicinae-window-management";
  version = "1.0.0";

  src = ../extensions/gnome-raycast-window-management;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    extensionDir="$out/share/gnome-shell/extensions/${uuid}"
    mkdir -p "$extensionDir"
    cp extension.js metadata.json "$extensionDir/"
    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta = {
    description = "Raycast-style GNOME window management service for Vicinae";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
