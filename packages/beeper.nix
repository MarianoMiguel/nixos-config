{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  makeWrapper,
  asar,
}:
let
  pname = "beeper";
  version = "4.3.34";
  src = fetchurl {
    url = "https://beeper-desktop.download.beeper.com/builds/Beeper-${version}-x86_64.AppImage";
    hash = "sha256-Y05Ce4CVjjg+T8qlFaMBFiiKREr7Yz0OTEqcVdH/TUI=";
  };
  # Beeper's current AppImage omits the legacy AI\x02 marker that
  # appimageTools.extract checks, although its bundled runtime can still
  # extract the SquashFS payload normally. Use that runtime for extraction.
  appimageContents = stdenvNoCC.mkDerivation {
    inherit pname version src;
    dontUnpack = true;
    nativeBuildInputs = [ asar ];

    installPhase = ''
      runHook preInstall

      cp "$src" Beeper.AppImage
      chmod +x Beeper.AppImage
      ./Beeper.AppImage --appimage-extract
      cp -a squashfs-root "$out"

      appRoot="$out/resources/app"
      ${lib.getExe asar} extract "$out/resources/app.asar" "$appRoot"
      rm "$out/resources/app.asar"

      # NixOS owns the launcher and application icon.
      linuxConfigFilename=$appRoot/build/main/linux-*.mjs
      echo "export function registerLinuxConfig() {}" > $linuxConfigFilename

      # The Nix package is immutable, so upgrades happen through this file.
      sed -i 's/c=d??{},p=c.hw_acceleration??!0/c={...(d??{}),auto_update_disabled:true},p=c.hw_acceleration??!0/g' $appRoot/build/main/index-*.mjs
      sed -i -E 's/executeDownload\([^)]+\)\{/executeDownload(){return;/g' $appRoot/build/main/main-entry-*.mjs

      # Do not display an in-app update error for the immutable package.
      sed -i '$ a\.subview-prefs-about > div:nth-child(2) {display: none;}' $appRoot/build-browser/*.css

      runHook postInstall
    '';
  };
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;

  extraPkgs = pkgs: [ pkgs.libsecret ];

  extraInstallCommands = ''
    install -Dm644 ${appimageContents}/beepertexts.png \
      $out/share/icons/hicolor/512x512/apps/beepertexts.png
    install -Dm644 ${appimageContents}/beepertexts.desktop \
      $out/share/applications/beepertexts.desktop
    substituteInPlace $out/share/applications/beepertexts.desktop \
      --replace-fail "AppRun" "beeper"

    . ${makeWrapper}/nix-support/setup-hook
    wrapProgram $out/bin/beeper \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}} --no-update" \
      --set APPIMAGE beeper \
      --run 'exec >/dev/null'
  '';

  meta = {
    description = "Universal chat app";
    longDescription = ''
      Beeper combines chats from many messaging and social networks in one
      desktop application.
    '';
    homepage = "https://www.beeper.com/";
    license = lib.licenses.unfree;
    mainProgram = "beeper";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
