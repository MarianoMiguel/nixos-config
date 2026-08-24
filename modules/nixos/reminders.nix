{ pkgs, ... }:

let
  reminder = pkgs.writeShellApplication {
    name = "mariano-reminder";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gum
      jq
      libnotify
      util-linux
    ];
    text = builtins.readFile ../../scripts/reminder.sh;
  };
in
{
  environment.systemPackages = [ reminder ];

  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/nixos-config/reminders 0700 - -"
  ];

  systemd.user.services.mariano-reminders = {
    description = "Deliver due desktop reminders";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${reminder}/bin/mariano-reminder deliver";
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
      ReadWritePaths = [ "%h/.local/state/nixos-config/reminders" ];
    };
  };

  systemd.user.timers.mariano-reminders = {
    description = "Check scheduled desktop reminders";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      Persistent = true;
      AccuracySec = "5s";
      Unit = "mariano-reminders.service";
    };
  };
}
