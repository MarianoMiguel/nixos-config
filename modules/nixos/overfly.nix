{ pkgs, ... }:

let
  # Overfly runs from a checkout built on this machine: scripts/server-build.sh produces
  # build-resources/standalone (server, static files, migrations). Rebuild there and
  # `systemctl --user restart overfly` to pick up a new version.
  appRoot = "/home/mariano/Development/personal/overfly";
  standalone = "${appRoot}/build-resources/standalone";
in
{
  # A user service, not a system one: Overfly reads ~/.claude and ~/.codex and keeps its own
  # data in ~/.overfly. Lingering keeps the service up while nobody is logged in, so the phone
  # can reach it through Tailscale at any time.
  users.users.mariano.linger = true;

  systemd.user.services.overfly = {
    description = "Overfly, the agent control panel";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "${standalone}/server.js";

    environment = {
      NODE_ENV = "production";
      PORT = "47391";
      HOSTNAME = "127.0.0.1";
      OVERFLY_MIGRATIONS_DIR = "${standalone}/drizzle";
      NEXT_TELEMETRY_DISABLED = "1";
    };

    # Live git status and worktree hygiene spawn git.
    path = [ pkgs.git ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = standalone;
      ExecStart = "${pkgs.nodejs_24}/bin/node --max-semi-space-size=64 ${standalone}/server.js";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Reachable on the tailnet over HTTPS for the phone, after a one-time
  #   tailscale serve --bg --https=443 http://127.0.0.1:47391
  # which tailscaled remembers across reboots.

  # An "app" in the launcher: Chrome in app mode on the local server, with the Overfly icon.
  home-manager.users.mariano.xdg.desktopEntries.overfly = {
    name = "Overfly";
    comment = "Agent control panel";
    exec = "google-chrome-stable --app=http://127.0.0.1:47391";
    icon = "${appRoot}/public/overfly.png";
    terminal = false;
    categories = [ "Development" ];
    # Chrome names an --app window after its origin and profile; matching it here gives the window this name and icon.
    settings.StartupWMClass = "chrome-127.0.0.1__-Default";
  };
}
