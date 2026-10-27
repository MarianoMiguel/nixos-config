{
  cmake,
  glib,
  kdePackages,
  lib,
  makeWrapper,
  networkmanager,
  ninja,
  pkg-config,
  python3,
  qt6,
  quickshell,
  runCommand,
  src,
  stdenv,
  tzdata,
  vicinae,
  xkeyboard-config,
}:

# Pond's shell, lock screen, screenshot preview and wallpaper, installed in the
# layout Pond's Arch packages use (pond-shell, pond-lockscreen, pond-screenshot,
# pond-wallpaper), with Arch's absolute paths moved to their NixOS equivalents.
# The install layout was read from Pond's published rootfs; see
# workshop/UPSTREAMS.md.
#
# Pond targets Arch's Qt 6.12 and Quickshell 0.3.2 (its QML uses 6.12-only
# alias targets), so callPackage this from the nixpkgs-pond set. $out/bin/qs
# is that Quickshell with Pond's QML modules on its import path, and every qs
# call in Pond is pointed at it; the DMS session keeps its own Quickshell.
let
  # Pond's settings helpers run `python3 <script>` and import PyQt6 and
  # PyGObject (Gio/GLib), which Arch provides as system packages.
  python = runCommand "pond-python" { nativeBuildInputs = [ makeWrapper ]; } ''
    makeWrapper ${
      python3.withPackages (ps: [
        ps.pygobject3
        ps.pyqt6
      ])
    }/bin/python3 $out/bin/python3 \
      --prefix GI_TYPELIB_PATH : ${glib.out}/lib/girepository-1.0
  '';

  qmlPrefix = qt6.qtbase.qtQmlPrefix;
in
stdenv.mkDerivation {
  pname = "pond-interface";
  version = "0-unstable-${src.lastModifiedDate or "unknown"}";
  inherit src;

  nativeBuildInputs = [
    cmake
    makeWrapper
    ninja
    pkg-config
  ];

  # KF6NetworkManagerQt's CMake config looks up libnm and gio-2.0 itself.
  buildInputs = [
    glib
    kdePackages.networkmanager-qt
    networkmanager
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # Nothing here is a Qt executable: the shell runs inside Quickshell.
  dontWrapQtApps = true;
  dontUseCmakeConfigure = true;

  postPatch = ''
    files=$(find shell lockscreen screenshot wallpaper config -type f \
      \( -name '*.qml' -o -name '*.js' -o -name '*.py' -o -name '*.kdl' \
         -o -name '*.jsonc' -o -name '*.desktop' -o -name '*.conf' \))

    # Arch keeps tools in /usr/bin. Keep Pond's absolute paths absolute and
    # move them to the NixOS system profile; Quickshell and the launcher are
    # Pond's own builds.
    sed -i -E \
      -e "s#/usr/bin/qs #$out/bin/qs #g" \
      -e "s#\"qs -#\"$out/bin/qs -#g" \
      -e "s#\"qs\"#\"$out/bin/qs\"#g" \
      -e "s#Exec=qs #Exec=$out/bin/qs #g" \
      -e "s#\\['qs',#['$out/bin/qs',#g" \
      -e 's#/usr/bin/env python3#${python}/bin/python3#g' \
      -e 's#/usr/bin/python3#${python}/bin/python3#g' \
      -e 's#"python3"#"${python}/bin/python3"#g' \
      -e 's#/usr/bin/vicinae#${vicinae}/bin/vicinae#g' \
      -e 's#\["vicinae"#["${vicinae}/bin/vicinae"#g' \
      -e 's#/usr/bin/([A-Za-z0-9_.-]+)#/run/current-system/sw/bin/\1#g' \
      -e "s#/usr/share/pond-interface#$out/share/pond-interface#g" \
      -e 's#/usr/share/zoneinfo/#${tzdata}/share/zoneinfo/#g' \
      -e 's#/usr/share/X11/xkb/#${xkeyboard-config}/share/X11/xkb/#g' \
      $files

    # The Pond session keeps its niri config in ~/.config/pond/niri so it
    # never touches the DMS session's ~/.config/niri. Fails loudly when
    # upstream changes these lines.
    substituteInPlace shell/settings/display/control.py \
      --replace-fail \
        "CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'niri'" \
        "CONFIG = Path(os.environ.get('POND_NIRI_CONFIG_DIR') or Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'niri')"
    substituteInPlace shell/settings/system/control.py \
      --replace-fail \
        "INPUT = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'niri/cfg/input.kdl'" \
        "INPUT = Path(os.environ.get('POND_NIRI_CONFIG_DIR') or Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'niri') / 'cfg/input.kdl'"
  '';

  buildPhase = ''
    runHook preBuild

    cmakeFlagsCommon=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON)
    cmake -S . -B build/wifi "''${cmakeFlagsCommon[@]}"
    cmake --build build/wifi
    cmake -S screenshot/native -B build/screenshot "''${cmakeFlagsCommon[@]}" -DCMAKE_INSTALL_PREFIX=$out
    cmake --build build/screenshot

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    qml=$out/${qmlPrefix}/Pond
    share=$out/share/pond-interface

    # pond-lockscreen: Pond.WifiStatus (plugin plus its backing library).
    mkdir -p $qml/WifiStatus
    cp -P build/wifi/Pond/WifiStatus/{qmldir,*.qmltypes} $qml/WifiStatus/
    find build/wifi -maxdepth 3 -name 'libpond_wifi_status*.so*' -exec cp -P {} $qml/WifiStatus/ \;

    # pond-screenshot: Pond.Screenshot and its native drag helper.
    cmake --install build/screenshot
    mkdir -p $qml/Screenshot
    mv $out/lib/qt6/qml/Pond/Screenshot/Native $qml/Screenshot/Native
    rm -r $out/lib/qt6
    cp -r screenshot/{Preview.qml,State.qml,clipboard.py,qmldir,assets} $qml/Screenshot/

    # pond-wallpaper: Pond.Wallpaper and Pond.Daylight.
    mkdir -p $qml/Wallpaper $qml/Daylight
    cp wallpaper/qmldir wallpaper/*.qml $qml/Wallpaper/
    cp -r wallpaper/daylight/. $qml/Daylight/

    # pond-shell and pond-lockscreen.
    mkdir -p $share
    cp -r shell lockscreen config $share/
    rm -rf $share/lockscreen/frontend/system
    install -Dm444 config/fastfetch/fastfetch-flowers.ttf $out/share/fonts/truetype/fastfetch-flowers.ttf
    install -Dm444 config/applications/pond-manual.desktop $out/share/applications/pond-manual.desktop
    install -Dm444 LICENSE $out/share/licenses/pond-interface/LICENSE

    makeWrapper ${quickshell}/bin/qs $out/bin/qs \
      --prefix NIXPKGS_QT6_QML_IMPORT_PATH : $out/${qmlPrefix}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # A new Arch path upstream must fail the build, not a button at runtime.
    if grep -rnE '/usr/(bin|share|local)/' \
        --include='*.qml' --include='*.js' --include='*.py' --include='*.kdl' \
        --include='*.jsonc' --include='*.desktop' --include='*.conf' \
        $out/share/pond-interface $out/${qmlPrefix} \
        | grep -v 'XDG_DATA_DIRS'; then
      echo "pond-interface: unrewritten Arch path (see above)" >&2
      exit 1
    fi
    # A qs call that escaped the rewrite would start the DMS session's
    # Quickshell (Qt 6.11), which cannot load Pond's QML.
    if grep -rnE "\"qs\"|'qs'|\"qs -|Exec=qs |[[:space:]]qs -[cpd]" \
        --include='*.qml' --include='*.py' --include='*.kdl' --include='*.desktop' \
        $out/share/pond-interface $out/share/applications; then
      echo "pond-interface: qs call not pointed at $out/bin/qs (see above)" >&2
      exit 1
    fi
    $out/bin/qs --version
    for module in WifiStatus Screenshot Screenshot/Native Wallpaper Daylight; do
      test -f $out/${qmlPrefix}/Pond/$module/qmldir
    done
    test -n "$(find $out/${qmlPrefix}/Pond/WifiStatus -name '*plugin*.so')"

    runHook postInstallCheck
  '';

  passthru = {
    inherit python qmlPrefix;
  };

  meta = {
    description = "Pond's desktop interface (shell, lock screen, screenshot, wallpaper) for NixOS";
    homepage = "https://github.com/bflycomputer/pond-interface";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
