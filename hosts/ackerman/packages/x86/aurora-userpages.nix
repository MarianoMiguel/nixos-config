# `userpages`, Aurora's launcher for per-process page sizes: `userpages 4k COMMAND` runs COMMAND and
# its descendants with 4K userspace pages on the 16K kernel (needs `user4k=on`). It uses the
# kernel's private PR_AURORA_* prctl numbers, so it comes from the kernel's own tree
# (tools/aurora-userpages): aurora-silicon/linux 2b05915f81bc, nixos-aurora's kernel pin, whose
# userpages.c, Makefile and include/uapi/linux/prctl.h are byte-identical to the J716C wave tree's
# (checked 2026-11-12). Only those files are fetched, not the kernel.
{
  lib,
  stdenv,
  fetchurl,
}:

let
  rev = "2b05915f81bc066670cd872be3cbdd916753bf26";
  file =
    path: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/aurora-silicon/linux/${rev}/${path}";
      name = "aurora-linux-" + builtins.baseNameOf path;
      inherit hash;
    };
in
stdenv.mkDerivation {
  pname = "aurora-userpages";
  version = "7.3.0-g" + builtins.substring 0 12 rev;

  # The tree's layout: userpages.c includes ../../include/uapi/linux/prctl.h
  dontUnpack = true;
  postPatch = "";
  buildPhase = ''
    runHook preBuild
    mkdir -p tools/aurora-userpages include/uapi/linux
    cp ${file "tools/aurora-userpages/userpages.c" "sha256-7Rg3OlbIAXX8ckecB0w4EzsbhLXn1zQnOc9kelPsZss="} tools/aurora-userpages/userpages.c
    cp ${file "tools/aurora-userpages/Makefile" "sha256-19AVJzJ/prYeGYutfUUC35QamFtc7DAe9VTpNa37S2U="} tools/aurora-userpages/Makefile
    cp ${file "include/uapi/linux/prctl.h" "sha256-GjCIYSor93XD7zT5QHKIhEG5w2L3wZ0oizHjvI40WT4="} include/uapi/linux/prctl.h
    make -C tools/aurora-userpages
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 tools/aurora-userpages/userpages $out/bin/userpages
    install -Dm644 ${file "tools/aurora-userpages/README.rst" "sha256-r1r+vbmRhnEbTthUqC/yQ9BZ2CGLQHjEmPbEYIDEhXg="} $out/share/doc/aurora-userpages/README.rst
    install -Dm644 ${file "COPYING" "sha256-+1pCW9OzzWBxo6mv+ZCahZ58EVjVTTLgdlg5jNZ+tqA="} $out/share/licenses/aurora-userpages/COPYING
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/userpages" --help | grep -q '{native|4k|16k|64k} COMMAND'
  '';

  meta = {
    description = "Run programs with 4K userspace pages on Aurora's 16K kernels";
    homepage = "https://github.com/aurora-silicon/linux/tree/${rev}/tools/aurora-userpages";
    license = lib.licenses.gpl2Only;
    mainProgram = "userpages";
    platforms = [ "aarch64-linux" ];
  };
}
