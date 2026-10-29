# Folio's Plymouth theme ("folio"): the boot and disk-unlock screen.
# modules/nixos/folio-boot.nix installs it; build.py draws it from Folio's
# palette, fonts and art (assets/azure-folio) for one fixed choice of paper,
# ink and plate, because the boot happens before any session can say which.
{
  lib,
  runCommand,
  python3,
  librsvg,
  # Argument names avoid nixpkgs attributes (callPackage would fill `ink`
  # and `art` with unrelated packages).
  machineName ? "Bonhart",
  folioMode ? "dark",
  folioInk ? "azure",
  folioArt ? "dore-nightfall",
  # Screen sizes the plate is printed for, pixel for pixel. Bonhart's
  # firmware console (and panel) is 1920x1200; 1920x1080 is the usual HDMI
  # mode a KVM capture asks for. Other sizes scale the nearest print.
  printSizes ? [
    "1920x1200"
    "1920x1080"
  ],
}:

assert lib.elem folioMode [
  "light"
  "dark"
];

let
  python = python3.withPackages (p: [ p.pillow ]);
in
runCommand "plymouth-theme-folio"
  {
    nativeBuildInputs = [
      python
      librsvg
    ];
    passthru.fonts = runCommand "plymouth-folio-fonts" { } ''
      # Inter and IBM Plex Mono for the strings Plymouth renders at boot
      # (systemd's prompt, messages, the console viewer).
      mkdir -p "$out"
      cp ${../../assets/azure-folio/fonts}/font-{0,1,2,3,4}.ttf "$out/"
    '';
    meta = {
      description = "Folio's Plymouth boot and disk-unlock screen";
      platforms = lib.platforms.linux;
    };
  }
  ''
    theme="$out/share/plymouth/themes/folio"
    python ${./build.py} \
      --assets ${../../assets/azure-folio} \
      --render ${../../tools/azure-folio/render.py} \
      --script ${./folio.script} \
      --out "$theme" \
      --name ${lib.escapeShellArg machineName} \
      --mode ${folioMode} \
      --ink ${lib.escapeShellArg folioInk} \
      --art ${lib.escapeShellArg folioArt} \
      ${lib.concatMapStringsSep " " (s: "--size ${lib.escapeShellArg s}") printSizes}
  ''
