{ pkgs }:

let
  upstream = pkgs.callPackage (pkgs.path + "/pkgs/misc/cups/drivers/hl1210w") { };
in
upstream.overrideAttrs (old: {
  # Nixpkgs evaluates the whole package with pkgsi686Linux even though only
  # Brother's vendor binaries are 32-bit. Build the wrappers with native tools
  # and retain the 32-bit glibc interpreter for those binaries instead.
  installPhase = old.installPhase + ''
    ${pkgs.patchelf}/bin/patchelf \
      --set-interpreter ${pkgs.pkgsi686Linux.glibc.out}/lib/ld-linux.so.2 \
      "$out/opt/brother/Printers/HL1210W/cupswrapper/brcupsconfig4"
  '';
})
