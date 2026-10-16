{ lib, stdenvNoCC, python3, makeWrapper, bash, systemd, openssh, gnugrep, coreutils }:
let
  python = python3.withPackages (ps: [ ps.fido2 ]);
in
stdenvNoCC.mkDerivation {
  pname = "bonhart-fido-bridge";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ../scripts/fido-bridge;
    filter = path: type:
      (type == "directory" && baseNameOf path != "__pycache__")
      || lib.hasSuffix ".py" path || lib.hasSuffix ".sh" path;
  };
  nativeBuildInputs = [ makeWrapper ];
  doCheck = true;
  checkPhase = ''
    ${python}/bin/python -m unittest -v test_bridge
  '';
  installPhase = ''
    mkdir -p "$out/libexec/fido-bridge" "$out/bin"
    cp bridge.py "$out/libexec/fido-bridge/"
    makeWrapper ${python}/bin/python "$out/libexec/remote-yubikey-worker" \
      --add-flags "$out/libexec/fido-bridge/bridge.py"
    cp remote-yubikey.sh "$out/bin/remote-yubikey"
    substituteInPlace "$out/bin/remote-yubikey" \
      --replace-fail '@worker@' "$out/libexec/remote-yubikey-worker"
    chmod +x "$out/bin/remote-yubikey"
    patchShebangs "$out/bin"
    wrapProgram "$out/bin/remote-yubikey" \
      --prefix PATH : ${lib.makeBinPath [ bash systemd openssh gnugrep coreutils ]}
  '';
  meta = {
    description = "On-demand YubiKey FIDO forwarding over SSH from the Mac to Bonhart";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "remote-yubikey";
  };
}
