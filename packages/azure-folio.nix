{ lib, stdenvNoCC, runCommand, python3, makeWrapper }:
let
  python = python3.withPackages (p: [ p.pillow ]);
  artwork = runCommand "azure-folio-artwork-1.0.0" {
    nativeBuildInputs = [ python ];
  } ''
    python ${../tools/azure-folio/build.py} ${../assets/azure-folio} "$out"
  '';
  # Typography/layout and neutral-color edits never re-dither the artwork.
  palettes = runCommand "azure-folio-palettes-1.0.0" {
    nativeBuildInputs = [ python3 ];
  } ''
    python ${../tools/azure-folio/palettes.py} ${../assets/azure-folio} "$out"
  '';
in
stdenvNoCC.mkDerivation {
  pname = "azure-folio";
  version = "1.0.0";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/azure-folio" "$out/share/fonts/truetype" "$out/bin"
    ln -s ${artwork}/art "$out/share/azure-folio/art"
    ln -s ${palettes} "$out/share/azure-folio/themes"
    cp ${artwork}/catalog.json "$out/share/azure-folio/"
    cp ${../assets/azure-folio/generation-prompts.json} "$out/share/azure-folio/"
    cp -R ${../assets/azure-folio/fonts} "$out/share/azure-folio/fonts"
    cp ${../assets/azure-folio/fonts}/*.ttf "$out/share/fonts/truetype/"
    cp ${../tools/azure-folio/azure_folio.py} "$out/share/azure-folio/azure_folio.py"
    substituteInPlace "$out/share/azure-folio/azure_folio.py" --replace-fail '@data@' "$out/share/azure-folio"
    makeWrapper ${python3}/bin/python3 "$out/bin/azure-folio" --add-flags "$out/share/azure-folio/azure_folio.py"
    runHook postInstall
  '';
  meta = {
    description = "Blue and ivory desktop art, typography and appearance controls";
    platforms = lib.platforms.linux;
    mainProgram = "azure-folio";
  };
}
