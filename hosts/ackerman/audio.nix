# ackerman's sound, as on the Arch daily (m5max-linux docs/status.md): PipeWire and WirePlumber
# with asahi-audio and the J716 profile (his convolver, the speakers' DSP leg held at 100 %),
# speakersafetyd watching the speaker sense (started by udev when the sense PCM appears, verbose
# so the listen guard can read its power lines). The kernel's -30 dB ceiling is gone since 2026-11-09
# (the cap kernel, after the speaker-sense check): the daemon's model is the limit.
{
  lib,
  pkgs,
  ...
}:

let
  audio = pkgs.callPackage ./packages/audio.nix { };
  ucm = "${audio.alsa-ucm}/share/alsa/ucm2";
in
{
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
    configPackages = [ audio.asahi-audio ];
    wireplumber.configPackages = [ audio.asahi-audio ];
    extraLv2Packages = audio.asahi-audio.passthru.requiredLv2Packages;
  };

  environment.variables.ALSA_CONFIG_UCM2 = ucm;
  systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucm;
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucm;

  systemd.packages = [ audio.speakersafetyd ];
  services.udev.packages = [ audio.speakersafetyd ];
  systemd.services.speakersafetyd.serviceConfig.ExecStart = [
    ""
    "${lib.getExe audio.speakersafetyd} -c ${audio.speakersafetyd}/share/speakersafetyd/ -m 7 -v"
  ];

  # The listening test's stop rules (his LISTENING-TEST.md): on a TAS2764 fault or a
  # speakersafetyd trip, mute the default sink and switch the speakers off. Never kills processes.
  systemd.services.m5max-listen-guard = {
    description = "Speaker stop-rule guard (m5max-linux)";
    after = [ "speakersafetyd.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      alsa-utils
      bash
      coreutils
      gnugrep
      gawk
      util-linux
      systemd
      wireplumber
      pulseaudio
    ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash ${./scripts/m5max-listen-guard}";
      Restart = "on-failure";
    };
  };

  environment.systemPackages = with pkgs; [
    alsa-utils
    pamixer
    pulseaudio
    sox
  ];
}
