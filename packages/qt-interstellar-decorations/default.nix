# Interstellar's title bar for Qt 6 apps (Dolphin, Kate, qBittorrent, OBS,
# opensnitch-ui...): a QtWayland client-side decoration plugin, selected with
# QT_WAYLAND_DECORATION=interstellar. Two lights at the start of the bar like
# the GTK apps', colours from themeport's kdeglobals and azure-folio's theme.
#
# Ported from QAdwaitaDecorations 0.1.7 (LGPL-2.1-or-later, Jan Grulich;
# workshop/UPSTREAMS.md). It uses Qt's private Wayland API, so it is built
# against this system's own qtbase: the plugin only paints for apps on that
# exact Qt and hands others Qt's default bar (plugin.cpp).
{
  lib,
  stdenv,
  cmake,
  qt6,
  wayland,
  libxkbcommon,
}:

stdenv.mkDerivation {
  pname = "qt-interstellar-decorations";
  version = "1.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.difference ./. ./default.nix;
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    qt6.qtbase
    wayland
    libxkbcommon
  ];

  dontWrapQtApps = true;

  cmakeFlags = [
    "-DQT_PLUGINS_DIR=${placeholder "out"}/${qt6.qtbase.qtPluginPrefix}"
  ];

  postInstall = ''
    install -Dm0644 ../LICENSE "$out/share/licenses/qt-interstellar-decorations/LICENSE"
  '';

  meta = {
    description = "Interstellar's title bar for Qt 6 Wayland apps (client-side decorations)";
    homepage = "https://github.com/FedoraQt/QAdwaitaDecorations";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
