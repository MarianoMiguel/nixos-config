{ pkgs, ... }:

let
  appRoot = "/home/mariano/Development/personal/tv-remotes";
in
{
  systemd.services.tv-remotes = {
    description = "Local Samsung and Android TV remote control";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
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
      ProtectHome = "read-only";
      ReadWritePaths = [ "${appRoot}/data" ];
    };
  };

  services.localWebHosting.applications.tv-remotes = {
    title = "TV Remotes";
    description = "Control the Samsung TV and Flowbox from any device on the local network.";
    path = "/tv";
    upstream = "http://127.0.0.1:4173";
  };
}
