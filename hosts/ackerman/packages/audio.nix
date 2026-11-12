# The J716C's speaker stack, at the versions the Arch daily runs (asahi-alarm: asahi-audio 4.1,
# speakersafetyd 2.0.1; nixpkgs 26.05 has 3.4 and 1.1.2) plus the J716 files that were added by
# hand there (rolotrealanis98/m5pro-linux's J716 profile, and the bring-up's own rules), copied
# from the Mac on 2026-11-08 into ../files/audio. Until 2026-11-09 the kernel held the speakers at a
# -30 dB ceiling; since the speaker-sense check passed, it holds them only while speakersafetyd doesn't.
{
  lib,
  stdenvNoCC,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  alsa-lib,
  alsa-ucm-conf,
  lsp-plugins,
  bankstown-lv2,
  triforce-lv2,
}:

let
  files = ../files/audio;
in
rec {
  speakersafetyd = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "speakersafetyd";
    version = "2.0.1";

    src = fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "speakersafetyd";
      tag = finalAttrs.version;
      hash = "sha256-duIPpTzZqVSZLxF/CYlxa1PPtnzeABTCYfZZ7lomkls=";
    };
    cargoHash = "sha256-gg1VcCrXKk5QsNvU7wz039md0gpFom6SrLuW6tjNQog=";

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ alsa-lib ];

    postPatch = ''
      substituteInPlace speakersafetyd.service --replace-fail /usr "$out"
    '';

    postInstall = ''
      make install-data DESTDIR=$out UNITDIR=/lib/systemd/system UDEVDIR=/lib/udev/rules.d SHAREDIR=/share
      # The J716 has no line in upstream's rule: start the daemon when its sense PCM appears.
      cat > $out/lib/udev/rules.d/96-speakersafetyd-j716.rules <<'EOF'
      SUBSYSTEM=="sound", KERNEL=="pcmC*D2c", ATTRS{id}=="AppleJ716", TAG+="systemd", ENV{SYSTEMD_WANTS}="speakersafetyd.service"
      EOF
      sed -i 's/^ *//' $out/lib/udev/rules.d/96-speakersafetyd-j716.rules
      # The J716's protection profile: his bring-up profile, the one the Arch daily runs
      install -Dm644 ${files}/speakersafetyd/apple/j716.conf $out/share/speakersafetyd/apple/j716.conf
    '';

    meta = {
      description = "Speaker protection daemon for Apple Silicon Macs, with the J716 profile";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "speakersafetyd";
    };
  });

  asahi-audio = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "asahi-audio-j716";
    version = "4.1";

    src = fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "asahi-audio";
      tag = "v${finalAttrs.version}";
      hash = "sha256-4UOng1M/nVE/2OkKf+kqCdea4mUCvktW2M0x5Um4CPI=";
    };

    makeFlags = [
      "DESTDIR=$(out)"
      "PREFIX=/"
      "DATA_DIR=share"
    ];

    postInstall = ''
      cp -r ${files}/asahi-audio/j716 $out/share/asahi-audio/j716
      chmod -R u+w $out/share/asahi-audio/j716
      install -Dm644 -t $out/share/wireplumber/wireplumber.conf.d ${files}/wireplumber/*.conf
    '';

    fixupPhase = ''
      runHook preFixup
      for f in $(find $out -type f -not -name '*.wav'); do
        substituteInPlace "$f" --replace-quiet /usr/share "$out/share"
      done
      runHook postFixup
    '';

    passthru.requiredLv2Packages = [
      lsp-plugins
      bankstown-lv2
      triforce-lv2
    ];

    meta = {
      description = "Asahi audio DSP configuration, with the J716 (16-inch M5) profile";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  });

  # ALSA's UCM tree, Asahi's at v10 (the Arch daily's; nixpkgs has 8, without aop_audio/3chan,
  # which the J716 microphones include), and the J716's two cards (macaudio: speakers and jack;
  # t8140-aop-audio: the microphones)
  alsa-ucm = stdenvNoCC.mkDerivation {
    pname = "alsa-ucm-conf-asahi-j716";
    version = "10";
    src = fetchFromGitHub {
      owner = "AsahiLinux";
      repo = "alsa-ucm-conf-asahi";
      tag = "v10";
      hash = "sha256-2A5HiaXRplAOi4M6qrihH8GyTT8+ANWs9DyCZhgE8pc=";
    };
    installPhase = ''
      mkdir -p $out/share/alsa
      cp -r ${alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/ucm2
      chmod -R u+w $out/share/alsa/ucm2
      cp -r ucm2/conf.d/. $out/share/alsa/ucm2/conf.d/
      cp -r ${files}/ucm2/conf.d/. $out/share/alsa/ucm2/conf.d/
    '';
  };
}
