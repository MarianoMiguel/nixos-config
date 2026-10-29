{ lib, stdenvNoCC, qt6, python3, unicode-emoji, cldr-annotations }:

# The Folio shell (dotfiles/quickshell/folio) with its shaders compiled. Run
# with `qs -c folio` once modules/nixos/folio-shell.nix links it into
# /etc/xdg/quickshell/folio.
stdenvNoCC.mkDerivation {
  pname = "folio-shell";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ../dotfiles/quickshell/folio;
    filter = path: _type: !(lib.hasSuffix ".qsb" path) && !(builtins.elem (baseNameOf path) [ "qmldir" "emoji.json" ]);
  };
  nativeBuildInputs = [ qt6.qtshadertools python3 ];
  # QML and shaders only: nothing to wrap.
  dontWrapQtApps = true;
  buildPhase = ''
    runHook preBuild
    for frag in shaders/*.frag; do
      qsb --glsl "300 es,330" -o "$frag.qsb" "$frag"
    done
    # Module folders load by URL; a qmldir makes their files types to each other.
    for dir in Modules/*/; do
      (cd "$dir" && for f in *.qml; do echo "''${f%.qml} 1.0 $f"; done) > "$dir/qmldir"
    done
    # The launcher's emoji: names and groups from Unicode, keywords from CLDR.
    python3 ${../scripts/folio-emoji} Modules/Launcher/emoji.json \
      --emoji-test ${unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      --cldr ${cldr-annotations}/share/unicode/cldr/common
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/folio-shell
    cp -r . $out/share/folio-shell/
    runHook postInstall
  '';
  meta.description = "Folio, the desktop shell of this configuration (Quickshell)";
}
