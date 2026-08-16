{
  asar,
  autoPatchelfHook,
  copyDesktopItems,
  electron_42,
  fetchurl,
  lib,
  makeDesktopItem,
  makeWrapper,
  node-gyp,
  nodejs,
  p7zip,
  python3,
  stdenv,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  inherit (source) version;
  installer = fetchurl {
    inherit (source) url hash;
  };
  desktopItem = makeDesktopItem {
    name = "granola";
    desktopName = "Granola";
    comment = "AI notepad for meetings";
    exec = "granola %u";
    icon = "granola";
    extraConfig = {
      Categories = "Office;";
      MimeType = "x-scheme-handler/granola;x-scheme-handler/granola-dev;";
    };
    startupWMClass = "Granola";
    startupNotify = true;
    terminal = false;
  };
in
stdenv.mkDerivation {
  pname = "granola-linux";
  inherit version;

  src = installer;
  dontUnpack = true;

  nativeBuildInputs = [
    asar
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
    node-gyp
    nodejs
    p7zip
    python3
  ];

  buildInputs = [ stdenv.cc.cc.lib ];
  desktopItems = [ desktopItem ];

  buildPhase = ''
    runHook preBuild

    mkdir installer windows app resources
    7z x -y -oinstaller "$src"
    7z x -y -owindows 'installer/$PLUGINSDIR/app-64.7z'
    asar extract windows/resources/app.asar app
    cp -a windows/resources/icons/. resources/icons/

    node ${./patch-linux.mjs} app

    sqlite_module=app/node_modules/better-sqlite3-multiple-ciphers
    install -Dm0644 ${./better-sqlite3-binding.gyp} "$sqlite_module/binding.gyp"

    export npm_config_nodedir=${electron_42.headers}
    node ${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js \
      rebuild \
      --target=${electron_42.version} \
      --release \
      --directory="$sqlite_module"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app_root="$out/share/granola"
    install -d "$app_root" "$out/bin" "$out/share/icons/hicolor/256x256/apps"
    cp -a app resources "$app_root/"
    install -Dm0644 ${./main.cjs} "$app_root/main.cjs"
    install -Dm0644 resources/icons/icon.png \
      "$out/share/icons/hicolor/256x256/apps/granola.png"

    makeWrapper ${electron_42}/bin/electron "$out/bin/granola" \
      --add-flags "$app_root" \
      --add-flags "--ozone-platform-hint=auto" \
      --add-flags "--enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer"

    runHook postInstall
  '';

  meta = {
    description = "Unofficial Linux package for the Granola meeting notepad";
    homepage = "https://www.granola.ai/";
    license = lib.licenses.unfree;
    mainProgram = "granola";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
