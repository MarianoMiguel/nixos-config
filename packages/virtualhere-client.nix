{
  lib,
  stdenv,
  fetchurl,
  upx,
  autoPatchelfHook,
  wrapGAppsHook3,
  gtk3,
  libGL,
  wayland,
  libxkbcommon,
  libx11,
  libsm,
  makeDesktopItem,
}:

stdenv.mkDerivation rec {
  pname = "virtualhere-client";
  version = "6.0.3";

  # Upstream uses moving URLs. Hashes pin the reviewed binaries; an upstream
  # replacement must fail the fetch rather than silently upgrade this client.
  src = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/vhuit64";
    hash = "sha256-8zl9pDpK13PL3TUGreSnYJRgUXnn6gKdJvlOkqvjvvE=";
  };
  consoleSrc = fetchurl {
    url = "https://www.virtualhere.com/sites/default/files/usbclient/vhclientx86_64";
    hash = "sha256-1m1BoS4RN8463sH4UZh6K/s8xiypaigGRqvNbZxOxVQ=";
  };

  dontUnpack = true;
  nativeBuildInputs = [
    upx
    autoPatchelfHook
    wrapGAppsHook3
  ];
  buildInputs = [
    gtk3
    libGL
    wayland
    libxkbcommon
    libx11
    libsm
    stdenv.cc.cc.lib
  ];
  desktopItems = [
    (makeDesktopItem {
      name = pname;
      desktopName = "VirtualHere USB Client";
      exec = "virtualhere-client -e";
      icon = "usb-creator";
      categories = [ "System" ];
      comment = "Connect a remote USB device (manual YubiKey forwarding trial)";
    })
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/virtualhere-client"
    # The GTK client is UPX-packed. Unpack before fixing its ELF interpreter
    # and library paths for NixOS. The console client is fully static.
    upx -d "$out/bin/virtualhere-client"
    install -Dm755 "$consoleSrc" "$out/bin/virtualhere-console"
    mkdir -p "$out/share/applications"
    cp ${builtins.head desktopItems}/share/applications/* "$out/share/applications/"
    runHook postInstall
  '';

  meta = {
    description = "USB over IP client for the remote YubiKey compatibility trial";
    homepage = "https://www.virtualhere.com/usb_client_software";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "virtualhere-client";
  };
}
