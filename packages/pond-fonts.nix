{
  fetchurl,
  stdenvNoCC,
  lib,
}:

# Pond depends on Arch's ttf-onest and ttf-advent-pro. nixpkgs only carries
# them inside the whole google-fonts tree, so pin the individual files from
# the same upstream repository instead.
let
  rev = "ddf386ba1b9fbc6b2c818f1ddcd9148f54ced94b";
  googleFont =
    path: name: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/${path}";
      inherit name hash;
    };
in
stdenvNoCC.mkDerivation {
  pname = "pond-fonts";
  version = "0-unstable-2026-10-27";

  srcs = [
    (googleFont "onest/Onest%5Bwght%5D.ttf" "Onest-wght.ttf"
      "sha256-lmxcKbR1XahLaFTVwh3U6qJCAiXQ6YdN5gLeF21KnzE="
    )
    (googleFont "adventpro/AdventPro%5Bwdth%2Cwght%5D.ttf" "AdventPro-wdth-wght.ttf"
      "sha256-tgqykguJvcS32t+ygsraxuA4M+eoCET56sCWNZsrl2Y="
    )
    (googleFont "adventpro/AdventPro-Italic%5Bwdth%2Cwght%5D.ttf" "AdventPro-Italic-wdth-wght.ttf"
      "sha256-CRel1lWJAl8qdSsbBWj5JNrEmgZaJbTWARazxtTZ664="
    )
  ];

  onestLicense = googleFont "onest/OFL.txt" "Onest-OFL.txt" "sha256-BxGV2IBuIm+u7mAlnCjKZ7RYInr1GVpz9c/KsG4wA7w=";
  adventProLicense = googleFont "adventpro/OFL.txt" "AdventPro-OFL.txt" "sha256-yNUramwqbEYZOkjU5txzaIlrx9TAafM6vKByhHaVeuw=";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    for font in $srcs; do
      install -Dm444 "$font" "$out/share/fonts/truetype/$(stripHash "$font")"
    done
    install -Dm444 "$onestLicense" "$out/share/licenses/pond-fonts/Onest-OFL.txt"
    install -Dm444 "$adventProLicense" "$out/share/licenses/pond-fonts/AdventPro-OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Onest and Advent Pro, the open fonts Pond's interface uses";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
