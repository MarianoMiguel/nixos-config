# Interstellar's Plymouth theme ("interstellar"): the boot and disk-unlock
# screen. modules/nixos/folio-boot.nix installs it; build.py draws it from
# Interstellar's looks (tools/azure-folio/looks.py), fonts and art for one
# look: a theme (Folio or Lumen), a mode and one color.
{
  lib,
  runCommand,
  python3,
  librsvg,
  inter,
  # Argument names avoid nixpkgs attributes (callPackage would fill `ink`
  # and `art` with unrelated packages).
  machineName ? "Bonhart",
  bootTheme ? "folio",
  folioMode ? "dark",
  # The theme's color: a name from its set (Folio's inks, Lumen's accents)
  # or #rrggbb.
  bootColor ? "azure",
  folioArt ? "dore-nightfall",
  # Screen sizes the art is printed for, pixel for pixel. Bonhart's
  # firmware console (and panel) is 1920x1200; 1920x1080 is the usual HDMI
  # mode a KVM capture asks for. Other sizes scale the nearest print.
  printSizes ? [
    "1920x1200"
    "1920x1080"
  ],
}:

assert lib.elem bootTheme [
  "folio"
  "lumen"
];
assert lib.elem folioMode [
  "light"
  "dark"
];

let
  python = python3.withPackages (p: [ p.pillow ]);

  # Inter Bold for Lumen's title, from Inter's own static collection
  # (build.py finds the face by name).
  boldFont = "${inter}/share/fonts/truetype/Inter.ttc";

  src = runCommand "interstellar-boot-src" { } ''
    mkdir -p "$out"
    cp ${./build.py} "$out/build.py"
    cp ${./interstellar.script} "$out/interstellar.script"
    cp ${../../tools/azure-folio/looks.py} "$out/looks.py"
    cp ${../../tools/azure-folio/render.py} "$out/render.py"
  '';

  # Everything a print needs besides the look itself: fixed when the system
  # is built.
  common = [
    "--assets"
    "${../../assets/azure-folio}"
    "--render"
    "${src}/render.py"
    "--looks"
    "${src}/looks.py"
    "--script"
    "${src}/interstellar.script"
    "--bold-font"
    boldFont
  ];
  machine = [
    "--name"
    machineName
    "--art"
    folioArt
  ]
  ++ lib.concatMap (s: [
    "--size"
    s
  ]) printSizes;

  fonts = runCommand "plymouth-interstellar-fonts" { } ''
    # Inter and IBM Plex Mono for the strings Plymouth renders at boot
    # (systemd's prompt, messages, the console viewer).
    mkdir -p "$out"
    cp ${../../assets/azure-folio/fonts}/font-{0,1,2,3,4}.ttf "$out/"
  '';
in
runCommand "plymouth-theme-interstellar"
  {
    nativeBuildInputs = [
      python
      librsvg
    ];
    passthru = {
      inherit fonts src;
    };
    meta = {
      description = "Interstellar's Plymouth boot and disk-unlock screen";
      platforms = lib.platforms.linux;
    };
  }
  ''
    theme="$out/share/plymouth/themes/interstellar"
    python ${src}/build.py ${lib.escapeShellArgs common} \
      --out "$theme" \
      --theme ${bootTheme} \
      --mode ${folioMode} \
      --pick ${lib.escapeShellArg bootColor} \
      ${lib.escapeShellArgs machine}
  ''
