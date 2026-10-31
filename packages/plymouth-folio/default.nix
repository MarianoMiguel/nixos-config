# Interstellar's Plymouth theme ("interstellar"): the boot and disk-unlock
# screen. modules/nixos/folio-boot.nix installs it; build.py draws it from
# Interstellar's looks (tools/azure-folio/looks.py), fonts and art for one
# look: a theme (Folio or Lumen), a mode and one color.
#
# This is the look built into the initrd. When the owner changes the
# desktop's look, passthru.publisher prints the same theme for the new look
# and writes it to the boot partition (boot_look.py), so the next boot
# follows without a rebuild.
{
  lib,
  runCommand,
  writeShellApplication,
  python3,
  librsvg,
  bash,
  coreutils,
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
  # Lumen's sky: orbit, prism, glow or haze (shaders/lumen.frag).
  bootSky ? "orbit",
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
assert lib.elem bootSky [
  "orbit"
  "prism"
  "glow"
  "haze"
];

let
  # numpy draws Lumen's skies per pixel, as the shader does; the system
  # already carries it.
  python = python3.withPackages (p: [
    p.pillow
    p.numpy
  ]);

  # Inter Bold for Lumen's title, from Inter's own static collection
  # (build.py finds the face by name).
  boldFont = "${inter}/share/fonts/truetype/Inter.ttc";

  src = runCommand "interstellar-boot-src" { } ''
    mkdir -p "$out"
    cp ${./build.py} "$out/build.py"
    cp ${./boot_look.py} "$out/boot_look.py"
    cp ${./interstellar.script} "$out/interstellar.script"
    cp ${../../tools/azure-folio/looks.py} "$out/looks.py"
    cp ${../../tools/azure-folio/render.py} "$out/render.py"
  '';

  # Everything a print needs besides the look itself: fixed when the system
  # is built, never read from the owner's files.
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

  # interstellar-boot-look publish|overlay: prints a look with the same
  # code and writes it as a boot archive (boot_look.py).
  publisher = writeShellApplication {
    name = "interstellar-boot-look";
    runtimeInputs = [ librsvg ];
    text = ''
      exec ${python}/bin/python3 -I ${src}/boot_look.py ${lib.escapeShellArgs (common ++ machine)} "$@"
    '';
  };

  fonts = runCommand "plymouth-interstellar-fonts" { } ''
    # Inter and IBM Plex Mono for the strings Plymouth renders at boot
    # (systemd's prompt, messages, the console viewer).
    mkdir -p "$out"
    cp ${../../assets/azure-folio/fonts}/font-{0,1,2,3,4}.ttf "$out/"
  '';

  # The unit tests: the checks on the published look, the archive and the
  # initrd's check of it (test_boot_look.py).
  tests =
    runCommand "interstellar-boot-tests"
      {
        nativeBuildInputs = [
          python
          librsvg
          bash
          coreutils
        ];
      }
      ''
        set -o pipefail
        export BOOT_LOOK_ARGS=${lib.escapeShellArg (builtins.toJSON (common ++ machine))}
        export BOOT_LOOK_CHECK=${./boot-look-check.sh}
        cp ${src}/*.py .
        cp ${./test_boot_look.py} test_boot_look.py
        python3 -m unittest -v test_boot_look 2>&1 | tee "$out"
      '';
in
runCommand "plymouth-theme-interstellar"
  {
    nativeBuildInputs = [
      python
      librsvg
    ];
    passthru = {
      inherit
        fonts
        publisher
        src
        tests
        ;
      checkScript = ./boot-look-check.sh;
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
      --sky ${bootSky} \
      ${lib.escapeShellArgs machine}
  ''
