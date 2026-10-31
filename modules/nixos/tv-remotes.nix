{ pkgs, ... }:

let
  appRoot = "/home/mariano/Development/personal/tv-remotes";
in
{
  systemd.services.tv-remotes = {
    description = "Local Samsung and Android TV remote control";
    wantedBy = [ "multi-user.target" ];
    # The server binds only to localhost and can start before Wi-Fi is online.
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "${appRoot}/src/server.js";

    environment = {
      NODE_ENV = "production";
      TV_REMOTES_HOST = "127.0.0.1";
      TV_REMOTES_PORT = "4173";
    };

    serviceConfig = {
      Type = "simple";
      User = "mariano";
      Group = "users";
      WorkingDirectory = appRoot;
      ExecStartPre = "${pkgs.coreutils}/bin/test -d ${appRoot}/node_modules";
      ExecStart = "${pkgs.nodejs_24}/bin/node ${appRoot}/src/server.js";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";

      # The service only needs to update its local pairing/device database.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      # Home is an empty tmpfs (no ~/.ssh, agent tokens or other projects).
      # The checkout comes back read-only: src/ and node_modules/ (code),
      # public/ (the web page) and config/devices.json (configured TVs);
      # data/ holds tv-remotes.json (devices and pairing credentials), which
      # the server rewrites through a temporary file in the same directory.
      ProtectHome = "tmpfs";
      BindReadOnlyPaths = [ appRoot ];
      BindPaths = [ "${appRoot}/data" ];
    };
  };

  services.localWebHosting.applications.tv-remotes = {
    title = "TV Remotes";
    description = "Control the Samsung TV and Flowbox from any device on the local network.";
    path = "/tv";
    upstream = "http://127.0.0.1:4173";
  };
}
