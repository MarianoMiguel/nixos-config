{ pkgs, ... }:

let
  appRoot = "/home/mariano/Development/personal/intervals";
in
{
  systemd.services.intervals = {
    description = "Air bike interval timer for BJJ conditioning";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "${appRoot}/src/server.js";

    environment = {
      NODE_ENV = "production";
      INTERVALS_HOST = "127.0.0.1";
      INTERVALS_PORT = "4174";
    };

    serviceConfig = {
      Type = "simple";
      User = "mariano";
      Group = "users";
      WorkingDirectory = appRoot;
      ExecStart = "${pkgs.nodejs_24}/bin/node ${appRoot}/src/server.js";
      Restart = "on-failure";
      RestartSec = 3;
      UMask = "0077";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
    };
  };

  services.localWebHosting.applications.intervals = {
    title = "Intervals";
    description = "Temporizador de air bike inspirado en el ritmo de combate de BJJ.";
    path = "/intervals";
    upstream = "http://127.0.0.1:4174";
  };
}
