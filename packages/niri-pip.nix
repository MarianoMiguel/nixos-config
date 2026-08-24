{
  coreutils,
  gum,
  lib,
  libnotify,
  makeWrapper,
  playerctl,
  rustPlatform,
  src,
  systemd,
}:

rustPlatform.buildRustPackage {
  pname = "niri-pip";
  version = "0.2.1";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoBuildFlags = [
    "--workspace"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--all-targets"
    "--locked"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    install -Dm0755 "$src/integrations/inir/niripip-menu" "$out/bin/niripip-menu"

    wrapProgram "$out/bin/niripip" \
      --prefix PATH : ${lib.makeBinPath [ playerctl systemd ]}
    wrapProgram "$out/bin/niripip-menu" \
      --set-default NIRIPIP_BIN "$out/bin/niripip" \
      --prefix PATH : ${lib.makeBinPath [ coreutils gum libnotify playerctl ]}
  '';

  meta = {
    description = "Sticky Picture-in-Picture and pinned-window controller for Niri";
    homepage = "https://github.com/t1ktakdev/niri-pip";
    license = lib.licenses.mit;
    mainProgram = "niripip";
    platforms = lib.platforms.linux;
  };
}
