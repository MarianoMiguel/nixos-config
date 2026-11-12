# FEX from Aurora's fork (aurora-silicon/fex 0c08727, "FEX-2610"), on nixpkgs' FEX recipe: the
# commit nixos-aurora and fedora-aurora (#250) build. Adapted from nixos-aurora's fex.nix (MIT):
# the fork's tree plus its submodules, each a pinned tarball (fex-aurora.json, copied from
# nixos-aurora's sources.json; every hash re-checked against codeload on 2026-11-12).
#
# Built with TUNE_CPU=none: FEX otherwise tunes for the build machine's CPU (-mcpu from
# /proc/cpuinfo), and Aurora saw SIGILL on Apple cores from a Neoverse build. Built on the Mac (no
# aarch64 cache hit for a fork); its build dependencies (the x86 cross compilers for the thunks)
# are the ones nixpkgs' own fex uses, which cache.nixos.org has for aarch64.
#
# The binary is `FEX` (2610 has no FEXInterpreter). nixpkgs' recipe turns its checks off on a
# 16K-page builder, as the Mac is.
{
  lib,
  fex,
  fetchurl,
  runCommand,
}:

let
  pin = lib.importJSON ./fex-aurora.json;
  short = builtins.substring 0 7 pin.commit;
  archive =
    name: record:
    fetchurl {
      name = "${name}-${record.commit}.tar.gz";
      url = record.source_url;
      hash = record.nix_hash;
    };
  src = runCommand "fex-${pin.version}-aurora-g${short}-source" { } (
    ''
      mkdir -p $out
      tar -xzf ${archive "fex" pin} --strip-components=1 -C $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: record: ''
        mkdir -p $out/${record.path}
        tar -xzf ${archive name record} --strip-components=1 -C $out/${record.path}
      '') pin.extra_sources
    )
  );
in
assert lib.assertMsg (
  pin.submodules_commit == pin.commit
) "fex-aurora.json: the submodule pins are for another FEX commit";
fex.overrideAttrs (
  _finalAttrs: old: {
    # nixpkgs' postPatch and OVERRIDE_VERSION make FEX-<version> the version string
    version = "${pin.version}-aurora-g${short}";
    inherit src;
    cmakeFlags = old.cmakeFlags ++ [ (lib.cmakeFeature "TUNE_CPU" "none") ];
    passthru = (old.passthru or { }) // {
      inherit (pin) commit;
    };
    meta = old.meta // {
      description = "Fast usermode x86 and x86-64 emulator for Arm64 Linux (Aurora's fork)";
      homepage = "https://github.com/aurora-silicon/fex";
      mainProgram = "FEX";
    };
  }
)
