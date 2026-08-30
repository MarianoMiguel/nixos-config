{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mariano.workspaceModes;

  niriModes = pkgs.runCommand "niri-modes" {
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.python3
    ];
  } ''
    install -Dm0755 ${../../scripts/niri-modes.py} "$out/libexec/niri-modes"
    patchShebangs "$out/libexec/niri-modes"
    makeWrapper "$out/libexec/niri-modes" "$out/bin/niri-modes" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.niri ]} \
      --set-default NIRI_MODES_FOCUS_WIDTH ${lib.escapeShellArg cfg.focusWidth}
  '';
in
{
  options.mariano.workspaceModes = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Per-workspace tile/float/focus modes for niri.";
    };

    focusWidth = lib.mkOption {
      type = lib.types.str;
      default = "80%";
      description = ''
        Column width used by focus mode. The single tabbed column is
        centered, so the rest of the screen shows only the wallpaper.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ niriModes ];

    systemd.user.services.niri-modes = {
      description = "Per-workspace window modes for niri";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      # The daemon is niri-specific; in GNOME or Plasma sessions it must not
      # start (and `niri msg` would have no socket to reach anyway).
      unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
      serviceConfig = {
        ExecStart = "${niriModes}/bin/niri-modes daemon";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
