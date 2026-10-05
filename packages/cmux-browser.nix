{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  patchelf,
  python3,
  addDriverRunpath,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  curl,
  dbus,
  expat,
  glib,
  gtk3,
  gsettings-desktop-schemas,
  libdrm,
  libgbm,
  libglvnd,
  libpulseaudio,
  libva,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxtst,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  vulkan-loader,
  wayland,
  xdg-utils,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cmux-browser";
  version = "151.0.7922.64";

  # This is the asset currently served by https://cmux.com/linux. Upstream's
  # nightly URL moves, so keep the version and content hash pinned together.
  src = fetchurl {
    url = "https://github.com/manaflow-ai/cmux-v2/releases/download/nightly/cmux-linux-x64.deb";
    name = "cmux-browser-${finalAttrs.version}-amd64.deb";
    hash = "sha256-zwNx7tqn/QpLRSFkck6s16IV6AY1hcagUue8OEysLgo=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    patchelf
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    libdrm
    libgbm
    libglvnd
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxtst
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
  ];

  # Chromium loads these with dlopen rather than linking them directly.
  runtimeDependencies = map lib.getLib [
    curl
    gtk3
    libpulseaudio
    libva
    pipewire
    vulkan-loader
    wayland
  ];

  unpackPhase = ''
    runHook preUnpack
    # Nix forbids setuid files. Chromium uses its unprivileged user-namespace
    # sandbox on NixOS, so the Debian setuid fallback is unnecessary.
    dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-permissions \
      --exclude=./opt/cmux/browser/chrome-sandbox
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt/cmux" "$out/bin" "$out/share"
    cp -a opt/cmux/browser "$out/opt/cmux/"
    cp -a usr/share/. "$out/share/"

    ${python3}/bin/python3 ${./cmux-browser/disable-linux-direct-retry.py} \
      "$out/opt/cmux/browser/chrome"

    # Desktop integration and updates belong to NixOS. Use the GTK backend
    # in Niri/GNOME and omit the optional Qt shims and Debian maintenance jobs.
    rm -rf "$out/opt/cmux/browser/cron" "$out/opt/cmux/browser/apparmor.d"
    rm "$out/opt/cmux/browser/libqt5_shim.so" "$out/opt/cmux/browser/libqt6_shim.so"
    rm "$out/opt/cmux/browser/cmux-browser"

    # The NixOS loader knows where the active system's GPU drivers live.
    rm "$out/opt/cmux/browser/libvulkan.so.1"
    ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 "$out/opt/cmux/browser/libvulkan.so.1"

    # Keep GLVND loaded for the process lifetime. The embedded terminal's
    # dlclose otherwise unloads libGL/GLX and triggers Chromium's dangling
    # pointer detector during startup on Niri. A direct dependency fixes the
    # lifetime without disabling checks or leaking LD_PRELOAD into shells.
    patchelf --add-needed libGL.so.1 "$out/opt/cmux/browser/chrome"

    makeWrapper "$out/opt/cmux/browser/chrome" "$out/bin/cmux-browser" \
      --set CHROME_WRAPPER "$out/bin/cmux-browser" \
      --set CHROME_VERSION_EXTRA stable \
      --add-flags '--class=cmux-browser' \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${addDriverRunpath.driverLink}/share" \
      --add-flags '--ozone-platform-hint=auto'
    ln -s cmux-browser "$out/bin/cmux-browser-stable"
    ln -s cmux-browser "$out/bin/cmux"
    ln -s "$out/opt/cmux/browser/cmux-tui" "$out/bin/cmux-tui"

    for desktop in "$out"/share/applications/*.desktop; do
      substituteInPlace "$desktop" \
        --replace-fail /usr/bin/cmux-browser-stable "$out/bin/cmux-browser"
    done

    for size in 16 24 32 48 64 128 256; do
      install -Dm644 "$out/opt/cmux/browser/product_logo_$size.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/cmux-browser.png"
    done

    runHook postInstall
  '';

  meta = {
    description = "Chromium browser and agent workspace with integrated Ghostty terminals";
    homepage = "https://cmux.com/linux";
    license = lib.licenses.gpl3Only;
    mainProgram = "cmux-browser";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
