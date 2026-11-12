# ackerman's thermal guards (m5max-linux docs/status.md, the CPU check and the GPU daily): the
# kernel's CPU backstop (passive at 100 C on the SoC die zone) is built in; on top of it, an
# interim CPU cap at about 3 GHz, and the session guard that logs the die every 250 ms and ends
# the compositor at 95 C. Undo the cap: `sudo systemctl stop m5-cpu-cap`.
{ pkgs, ... }:

let
  path = with pkgs; [
    bash
    coreutils
    gawk
    gnugrep
    gnused
    findutils
    procps
    util-linux
  ];
in
{
  systemd.services.m5-cpu-cap = {
    description = "J716C interim CPU frequency cap (about 3 GHz)";
    wantedBy = [ "multi-user.target" ];
    inherit path;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${./scripts/m5-cpu-cap}";
      ExecStop = "${pkgs.bash}/bin/bash ${./scripts/m5-cpu-cap} off";
    };
  };

  # Builds stay gentle while Mariano uses the Mac (2026-11-08 19:2x: a full-speed build pushed the
  # session to the 95 C guard): one job, 4 cores, idle CPU and IO scheduling, only on the CPU 12-17
  # cluster. The session guard below freezes the build at 90 C and resumes it below 80 C, before it
  # would end the compositor at 95 C.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  nix.settings = {
    max-jobs = 1;
    cores = 4;
  };
  systemd.services.nix-daemon.serviceConfig = {
    AllowedCPUs = "12-17";
    CPUWeight = 1;
    IOWeight = 1;
  };

  systemd.services.m5-session-guard = {
    description = "J716C GPU session thermal watch (freezes the Nix build at 90 C, ends the compositor at 95 C)";
    after = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    inherit path;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash ${./scripts/m5-session-guard}";
      Restart = "on-failure";
      RestartSec = 1;
      Nice = -5;
    };
  };
}
