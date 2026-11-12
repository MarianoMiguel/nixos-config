{ pkgs, ... }:

let
  capture = pkgs.writeShellApplication {
    name = "mariano-capture";
    runtimeInputs = with pkgs; [
      coreutils
      ffmpeg-headless
      gawk
      gnugrep
      grim
      jq
      libnotify
      pulseaudio
      slurp
      systemd
      util-linux
      wf-recorder
      wl-clipboard
    ];
    text = builtins.readFile ../../scripts/capture.sh;
  };
in
{
  environment.systemPackages = [ capture ];

  systemd.user.tmpfiles.rules = [
    "d %h/Pictures/Screenshots 0700 - -"
    "d %h/Videos/Recordings 0700 - -"
  ];

  systemd.user.services.mariano-capture-video = {
    description = "Mariano region screen recording";
    partOf = [ "graphical-session.target" ];
    unitConfig = {
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
      StartLimitIntervalSec = 30;
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Type = "exec";
      ExecStart = "${capture}/bin/mariano-capture record-service";
      ExecStartPost = "${capture}/bin/mariano-capture record-started";
      ExecStopPost = "${capture}/bin/mariano-capture record-finished";
      Restart = "no";
      KillSignal = "SIGINT";
      TimeoutStopSec = 15;

      RuntimeDirectory = "mariano-capture";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = "read-only";
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      CapabilityBoundingSet = "";
      LockPersonality = true;
      SystemCallArchitectures = "native";
      ReadWritePaths = [ "%h/Videos/Recordings" ];

      Nice = 5;
      CPUWeight = 50;
      IOWeight = 50;
    };
  };
}
