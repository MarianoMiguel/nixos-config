{ niri-pip, pkgs, ... }:

let
  niriPip = pkgs.callPackage ../../packages/niri-pip.nix {
    src = niri-pip;
  };
in
{
  environment.systemPackages = [ niriPip ];

  # The small configuration intentionally relies on the application's
  # validated built-in browser detectors. It leaves no runtime plugin or
  # downloaded rule surface, while making the behavioral policy explicit.
  home-manager.users.mariano.xdg.configFile."niri-pip/config.toml" = {
    force = true;
    text = ''
      [general]
      enabled = true
      auto_detect = true
      follow_workspace = true
      follow_mode = "follow-workspace"
      remember_geometry = true
      restore_layout_on_unpin = true

      [pip]
      position = "bottom-right"
      position_mode = "remember"
      profile = "medium"
      steal_focus = false
      preserve_aspect_ratio = true

      [logging]
      level = "info"
    '';
  };

  systemd.user.services.niripip = {
    description = "Niri Picture-in-Picture controller";
    documentation = [ "https://github.com/t1ktakdev/niri-pip" ];
    wantedBy = [ "graphical-session.target" ];
    partOf = [
      "graphical-session.target"
      "niri.service"
    ];
    after = [
      "graphical-session.target"
      "niri.service"
    ];
    unitConfig = {
      ConditionEnvironment = "NIRI_SOCKET";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      ExecStart = "${niriPip}/bin/niripipd";
      ExecReload = "${niriPip}/bin/niripip reload";
      Restart = "always";
      RestartSec = 1;
      TimeoutStopSec = 5;
      KillMode = "control-group";
      RuntimeDirectory = "niri-pip";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "niri-pip";
      StateDirectoryMode = "0700";

      # This is an unprivileged, local-only daemon. Restrict it to Niri's Unix
      # socket plus the two directories that hold geometry and opacity state.
      NoNewPrivileges = true;
      UMask = "0077";
      CapabilityBoundingSet = "";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = "read-only";
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "%h/.config/niri" ];
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
    };
  };
}
