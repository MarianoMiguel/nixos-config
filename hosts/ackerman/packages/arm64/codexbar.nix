# CodexBar's CLI for aarch64: the same v0.55.0 release bonhart runs (gnome.nix), its official
# linux-aarch64 tarball, wrapped the same way (the Codex probe pointed at nixpkgs' codex). Only the
# CLI: bonhart's GNOME extension has no place on DMS, and session.nix keeps DMS plugins (such as
# dms-codexbar) off.
{
  lib,
  stdenvNoCC,
  fetchzip,
  autoPatchelfHook,
  curl,
  sqlite,
  stdenv,
  symlinkJoin,
  coreutils,
  runtimeShell,
  codex,
}:

let
  unwrapped = stdenvNoCC.mkDerivation {
    pname = "codexbar-unwrapped";
    version = "0.55.0";
    src = fetchzip {
      url = "https://github.com/steipete/CodexBar/releases/download/v0.55.0/CodexBarCLI-v0.55.0-linux-aarch64.tar.gz";
      hash = "sha256-9v+YcYP/RtIOUxdBSGcLHvMTY/dJnh4xlbRLprbHJlc=";
      stripRoot = false;
    };
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [
      curl
      sqlite
      stdenv.cc.cc.lib
    ];
    installPhase = ''
      runHook preInstall
      install -Dm0755 codexbar "$out/bin/codexbar"
      install -Dm0755 CodexBarCLI "$out/bin/CodexBarCLI"
      cp -R CodexBar_CodexBarCore.bundle "$out/bin/"
      install -Dm0644 VERSION "$out/bin/VERSION"
      runHook postInstall
    '';
    meta.platforms = [ "aarch64-linux" ];
  };
in
symlinkJoin {
  name = "codexbar-${unwrapped.version}";
  paths = [ unwrapped ];
  postBuild = ''
    for binary in codexbar CodexBarCLI; do
      rm "$out/bin/$binary"
      ${coreutils}/bin/tee "$out/bin/$binary" >/dev/null <<EOF
    #!${runtimeShell}
    export PATH="\$HOME/.local/bin:\$PATH"
    export CODEX_CLI_PATH="${codex}/bin/codex"
    exec "${unwrapped}/bin/$binary" "\$@"
    EOF
      chmod 0755 "$out/bin/$binary"
    done
  '';
  meta = {
    description = "CodexBar's usage CLI for Codex and other agents";
    homepage = "https://github.com/steipete/CodexBar";
    license = lib.licenses.mit;
    mainProgram = "codexbar";
    platforms = [ "aarch64-linux" ];
  };
}
